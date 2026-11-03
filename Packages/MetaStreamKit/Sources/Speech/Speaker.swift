import CoreModel
import CoreUI
import Foundation
import Goal
import SwiftUI
import AVFoundation

// ChatEvent lives in ChatFeed.swift — the producer owns the type.

/// Text-to-speech with three priority lanes: System (interrupts, never dropped, never muted), Alert (tips/follows/
/// subs/raids/ad-breaks, queued) and Chat (chat messages, queued and rate-limited). One AVSpeechSynthesizer utterance
/// plays at a time; `speakNext()` picks the highest-priority non-empty lane each time it's free to speak.
@MainActor
public final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    // Settings the view can bind to (voice/rate picker, per-kind toggles, min-tip slider).
    @AppStorage("ttsVoiceID") public var voiceID = ""            // AVSpeechSynthesisVoice identifier; empty = system default
    @AppStorage("ttsRate") public var rate: Double = 0.5          // AVSpeechUtteranceDefaultSpeechRate
    @AppStorage("ttsMinTipCents") public var minTipCents = 0
    @AppStorage("ttsMessagesOn") public var messagesOn = true
    @AppStorage("ttsTipsOn") public var tipsOn = true
    @AppStorage("ttsFollowsOn") public var followsOn = true
    @AppStorage("ttsSubsOn") public var subsOn = true
    @AppStorage("ttsRaidsOn") public var raidsOn = true
    @AppStorage("ttsIgnore") public var ignored = ""             // names never read, comma or space separated
    @AppStorage("ttsBlocked") public var blocked = ""            // extra words that stop a message being read, comma separated

    @Published public var muted = false
    // ponytail: intentional and not to be "simplified" away — mute only silences Alert/Chat below.
    // A streamer who muted TTS because chat got noisy still needs to hear their stream died (System lane).
    public var showOrigin = false   // caller sets this when more than one chat origin is live, e.g. "on Kick, Bob says …"
    /// Set by the app wiring: bot lines Read aloud › Bots keeps quiet, and the app bot's own lines (Android: same hook).
    public var skipMessage: (ChatEvent) -> Bool = { _ in false }

    private let synth = AVSpeechSynthesizer()
    private var systemQueue: [String] = []   // unbounded: System is never dropped
    private var alertQueue: [String] = []
    private var chatQueue: [String] = []
    private var chatSpokenAt: [Date] = []    // sliding 60s window for the chat rate limit
    private let laneCap = 5
    private let chatPerMinuteCap = 20
    private var repeating: [String: Task<Void, Never>] = [:]
    private var lastChatter = ""            // a run of messages from one person names them once

    public override init() {
        super.init()
        synth.delegate = self
        // ponytail: usesApplicationAudioSession=false gives TTS its own ambient/mixed session instead of this
        // file touching AVAudioSession category (Streamer.swift already owns that for the RTMP mic pipeline).
        // Known ceiling: with the glasses HFP mic selected, the open-ear speaker can bleed back into the mic —
        // the Settings UI should warn about that, not code around it.
        synth.usesApplicationAudioSession = false
        // ponytail: 5 s poll so a chat message waiting on the per-minute cap gets spoken once it frees up,
        // instead of scheduling a wake timer per queued message.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.speakNext()
            }
        }
    }

    // MARK: System lane

    public func speakSystem(_ text: String) {
        systemQueue.append(text)
        if synth.isSpeaking { synth.stopSpeaking(at: .word) } else { speakNext() }
    }

    /// Speaks `text` now, then again at 30 s / 60 s / 2 min while the condition persists (call `stopRepeating`
    /// once it clears). Re-calling with the same `id` while already repeating is a no-op.
    public func startRepeating(id: String, text: String) {
        guard repeating[id] == nil else { return }
        speakSystem(text)
        repeating[id] = Task { [weak self] in
            for delay in [30, 60, 120] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                self.speakSystem(text)
            }
        }
    }

    /// Stops the repeat schedule for `id`; pass `recovered` to announce recovery once, on the System lane.
    public func stopRepeating(id: String, recovered: String? = nil) {
        repeating[id]?.cancel()
        repeating[id] = nil
        if let recovered { speakSystem(recovered) }
    }

    // MARK: Alert lane

    /// Generic alert with no template, e.g. "ad break in 90 seconds".
    public func speakAlert(_ text: String) {
        enqueue(String(text.prefix(200)), into: &alertQueue)
        speakIfIdle()
    }

    // MARK: Chat lane + templated alerts (tip/follow/subscribe/raid)

    public func speak(_ event: ChatEvent) {
        guard event.origin != "test", !event.flagged, var text = sentence(for: event) else { return }   // "test" = flood test   // mute is enforced in enqueue(_:into:)
        if showOrigin, !event.origin.isEmpty { text = "on \(event.origin), " + text }
        switch event.kind {
        case .message: enqueue(text, into: &chatQueue)
        default: enqueue(text, into: &alertQueue)
        }
        speakIfIdle()
    }

    private func sentence(for e: ChatEvent) -> String? {
        // Reading a slur aloud on stream can get the streamer banned, even when a viewer typed it.
        let user = ChatFilter.isBlocked(e.user, extra: blocked) ? "someone" : e.user
        let note = ChatFilter.isBlocked(e.text, extra: blocked) ? "" : ChatFilter.sanitize(e.text)
        switch e.kind {
        case .message:
            guard messagesOn, !ChatFilter.isNoise(user: e.user, text: e.text, ignored: ignored), !note.isEmpty,
                  !skipMessage(e) else { return nil }
            defer { lastChatter = e.user }
            return e.user == lastChatter ? note : "\(user) says \(note)"
        case .tip:
            let m = e.tipMoney
            let usdCents = Rates.shared.convert(m, to: "USD").map { NSDecimalNumber(decimal: $0 * 100).intValue } ?? 0   // unknown rate: read only when no minimum is set (fail closed)
            guard tipsOn, usdCents >= minTipCents else { return nil }
            let amount = Self.spokenMoney(m)
            return note.isEmpty ? "\(user) tipped \(amount)" : "\(user) tipped \(amount): \(note)"
        case .follow:
            return followsOn ? "\(user) followed" : nil
        case .subscribe:
            return subsOn ? "\(user) subscribed" : nil
        case .cheer:
            guard tipsOn else { return nil }   // bits are money; same gate as tips
            return note.isEmpty ? "\(user) cheered \(e.count) \(e.cheerUnit)" : "\(user) cheered \(e.count) \(e.cheerUnit): \(note)"
        case .raid:
            return raidsOn ? "\(user) raided with \(e.count) viewers" : nil
        }
    }

    private func enqueue(_ text: String, into queue: inout [String]) {
        guard !muted else { return }
        pushBounded(text, into: &queue)
    }

    /// Kept out of enqueue: `queue` is under exclusive (inout) access for that whole call, and speakNext() reading the
    /// same queue inside it is a runtime exclusivity violation -- the SIGABRT "crash after a few chats".
    private func speakIfIdle() {
        if !synth.isSpeaking { speakNext() }
    }

    private func pushBounded(_ text: String, into queue: inout [String]) {
        queue.append(text)
        if queue.count > laneCap { queue.removeFirst() }   // drop OLDEST: freshness beats completeness
    }

    // MARK: queue engine

    private func speakNext() {
        guard !synth.isSpeaking else { return }
        if !systemQueue.isEmpty {
            speakNow(systemQueue.removeFirst())
        } else if !muted, !alertQueue.isEmpty {
            speakNow(alertQueue.removeFirst())
        } else if !muted, !chatQueue.isEmpty, chatUnderRateLimit() {
            chatSpokenAt.append(Date())
            speakNow(chatQueue.removeFirst())
        }
    }

    private func chatUnderRateLimit() -> Bool {
        let cutoff = Date().addingTimeInterval(-60)
        chatSpokenAt.removeAll { $0 < cutoff }
        return chatSpokenAt.count < chatPerMinuteCap
    }

    private func speakNow(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = voiceID.isEmpty ? Self.bestVoice : AVSpeechSynthesisVoice(identifier: voiceID) ?? Self.bestVoice
        u.rate = Float(rate)
        synth.speak(u)
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.speakNext() }
    }
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.speakNext() }
    }

    // MARK: text shaping

    /// The best installed voice for the system language (Premium > Enhanced), nil = iOS default. iOS's own default is the
    /// robotic compact voice even when a Premium one is downloaded. Once per launch: speechVoices() is slow.
    public static let bestVoice: AVSpeechSynthesisVoice? = {
        // Any region of the language: "en-DE" has no voices of its own, so it must match en-US/en-GB; the exact one wins ties.
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = lang.prefix { $0 != "-" } + "-"
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { ($0.quality.rawValue, $0.language == lang ? 1 : 0) < ($1.quality.rawValue, $1.language == lang ? 1 : 0) }
        return best?.quality == .default ? nil : best
    }()

    /// "one million toman", "ten euros", "five dollars and fifty cents"; other currencies as a plain number and code.
    public static func spokenMoney(_ money: Money) -> String {
        let m = money.inToman
        guard m.amount > 0 else { return "money" }
        let f = NumberFormatter(); f.numberStyle = .spellOut; f.locale = Locale(identifier: "en_US")
        func words(_ d: Decimal) -> String { f.string(from: d as NSDecimalNumber) ?? "\(d)" }
        let unit: (String, String)
        switch m.currency {
        case "IRT": unit = ("toman", "toman")
        case "EUR": unit = ("euro", "euros")
        case "USD": unit = ("dollar", "dollars")
        default: return "\(m.amount) \(m.currency)"
        }
        let amount = m.amount.rounded(m.currency == "IRT" ? 0 : 2)
        var whole = Decimal(), rest = amount
        NSDecimalRound(&whole, &rest, 0, .down)
        let cents = NSDecimalNumber(decimal: (amount - whole) * 100).intValue
        var s = whole == 0 && cents > 0 ? "" : "\(words(whole)) \(whole == 1 ? unit.0 : unit.1)"
        if cents > 0 { s += (s.isEmpty ? "" : " and ") + "\(words(Decimal(cents))) cent\(cents == 1 ? "" : "s")" }
        return s
    }

    /// Spells whole-dollar amounts ("five dollars"); anything with cents stays a plain number ("12.50 dollars").
    public static func spokenAmount(cents: Int) -> String {
        guard cents > 0 else { return "money" }
        let dollars = cents / 100
        guard cents % 100 == 0 else { return String(format: "%.2f dollars", Double(cents) / 100) }
        let f = NumberFormatter(); f.numberStyle = .spellOut
        let words = f.string(from: NSNumber(value: dollars)) ?? String(dollars)
        return "\(words) dollar\(dollars == 1 ? "" : "s")"
    }
}
