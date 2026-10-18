import Foundation
import SwiftUI
import AVFoundation

// ChatEvent lives in ChatFeed.swift — the producer owns the type.

/// Text-to-speech with three priority lanes: System (interrupts, never dropped, never muted), Alert (tips/follows/
/// subs/raids/ad-breaks, queued) and Chat (chat messages, queued and rate-limited). One AVSpeechSynthesizer utterance
/// plays at a time; `speakNext()` picks the highest-priority non-empty lane each time it's free to speak.
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    // Settings the view can bind to (voice/rate picker, per-kind toggles, min-tip slider).
    @AppStorage("ttsVoiceID") var voiceID = ""            // AVSpeechSynthesisVoice identifier; empty = system default
    @AppStorage("ttsRate") var rate: Double = 0.5          // AVSpeechUtteranceDefaultSpeechRate
    @AppStorage("ttsMinTipCents") var minTipCents = 0
    @AppStorage("ttsMessagesOn") var messagesOn = true
    @AppStorage("ttsTipsOn") var tipsOn = true
    @AppStorage("ttsFollowsOn") var followsOn = true
    @AppStorage("ttsSubsOn") var subsOn = true
    @AppStorage("ttsRaidsOn") var raidsOn = true
    @AppStorage("ttsIgnore") var ignored = ""             // names never read, comma or space separated
    @AppStorage("ttsBlocked") var blocked = ""            // extra words that stop a message being read, comma separated

    @Published var muted = false
    // ponytail: intentional and not to be "simplified" away — mute only silences Alert/Chat below.
    // A streamer who muted TTS because chat got noisy still needs to hear their stream died (System lane).
    var showOrigin = false   // caller sets this when more than one chat origin is live, e.g. "on Kick, Bob says …"

    private let synth = AVSpeechSynthesizer()
    private var systemQueue: [String] = []   // unbounded: System is never dropped
    private var alertQueue: [String] = []
    private var chatQueue: [String] = []
    private var chatSpokenAt: [Date] = []    // sliding 60s window for the chat rate limit
    private let laneCap = 5
    private let chatPerMinuteCap = 20
    private var repeating: [String: Task<Void, Never>] = [:]
    private var lastChatter = ""            // a run of messages from one person names them once

    override init() {
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

    func speakSystem(_ text: String) {
        systemQueue.append(text)
        if synth.isSpeaking { synth.stopSpeaking(at: .word) } else { speakNext() }
    }

    /// Speaks `text` now, then again at 30 s / 60 s / 2 min while the condition persists (call `stopRepeating`
    /// once it clears). Re-calling with the same `id` while already repeating is a no-op.
    func startRepeating(id: String, text: String) {
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
    func stopRepeating(id: String, recovered: String? = nil) {
        repeating[id]?.cancel()
        repeating[id] = nil
        if let recovered { speakSystem(recovered) }
    }

    // MARK: Alert lane

    /// Generic alert with no template, e.g. "ad break in 90 seconds".
    func speakAlert(_ text: String) {
        enqueue(String(text.prefix(200)), into: &alertQueue)
        speakIfIdle()
    }

    // MARK: Chat lane + templated alerts (tip/follow/subscribe/raid)

    func speak(_ event: ChatEvent) {
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
        let user = Self.isBlocked(e.user, extra: blocked) ? "someone" : e.user
        let note = Self.isBlocked(e.text, extra: blocked) ? "" : Self.sanitize(e.text)
        switch e.kind {
        case .message:
            guard messagesOn, !Self.isNoise(user: e.user, text: e.text, ignored: ignored), !note.isEmpty, BotList.reads(e.user, e.text),
                  !AppBot.shared.isOwn(e) else { return nil }
            defer { lastChatter = e.user }
            return e.user == lastChatter ? note : "\(user) says \(note)"
        case .tip:
            let m = e.tipMoney
            let usdCents = Rates.shared.convert(m, to: "USD").map { NSDecimalNumber(decimal: $0 * 100).intValue } ?? Int.max   // unknown rate: read it
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

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.speakNext() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.speakNext() }
    }

    // MARK: text shaping

    /// The best installed voice for the system language (Premium > Enhanced), nil = iOS default. iOS's own default is the
    /// robotic compact voice even when a Premium one is downloaded. Once per launch: speechVoices() is slow.
    static let bestVoice: AVSpeechSynthesisVoice? = {
        // Any region of the language: "en-DE" has no voices of its own, so it must match en-US/en-GB; the exact one wins ties.
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = lang.prefix { $0 != "-" } + "-"
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { ($0.quality.rawValue, $0.language == lang ? 1 : 0) < ($1.quality.rawValue, $1.language == lang ? 1 : 0) }
        return best?.quality == .default ? nil : best
    }()

    // ponytail: the slurs and self-harm phrases most often behind hateful-conduct bans; `blocked` adds any language.
    nonisolated static let bannedTerms = ["nigger", "nigga", "faggot", "fag", "retard", "tranny", "kike", "chink", "spic",
                              "wetback", "gook", "kys", "kill yourself", "heil hitler"]
    private nonisolated static let squashedBanned = bannedTerms.map(squash)   // the widgets check every row many times a second
    private nonisolated static let leet: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
                                                       "@": "a", "$": "s", "!": "i", "|": "i"]

    /// Lowercased letters only, leetspeak undone and repeats collapsed: "N1iiGG3R" -> "niger".
    nonisolated static func squash(_ s: String) -> String {
        var out = ""
        for raw in s.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
            let c = leet[raw] ?? raw
            if c.isLetter, out.last != c { out.append(c) }
        }
        return out
    }

    /// True if `text` holds a banned term or one of `extra` (comma separated), through leetspeak and stretched letters;
    /// terms of 5+ letters also through spacing ("n i g g e r"). Shorter ones match whole words only, so "spicy" passes.
    /// ponytail: errs toward silence; a skipped harmless message costs nothing, a spoken slur can cost the channel.
    nonisolated static func isBlocked(_ text: String, extra: String) -> Bool {
        let terms = squashedBanned + extra.split(separator: ",").map { squash(String($0)) }.filter { !$0.isEmpty }
        let words = text.split { !$0.isLetter && leet[$0] == nil }.map { squash(String($0)) }
        let joined = squash(text)
        return terms.contains { t in t.count >= 5 ? joined.contains(t) : words.contains { $0 == t || $0 == t + "s" } }
    }

    /// !commands and names in `ignored`. Bots are decided separately (BotList + botReadMode).
    static func isNoise(user: String, text: String, ignored: String) -> Bool {
        let u = user.lowercased()
        let names = ignored.lowercased().split { $0 == "," || $0.isWhitespace }.map { $0.hasPrefix("@") ? String($0.dropFirst()) : String($0) }
        // Skip spaces, line breaks and invisible format characters (zero-width space, BOM) before the "!".
        let start = text.unicodeScalars.drop { $0.properties.isWhitespace || $0.properties.generalCategory == .format }
        return names.contains(u) || start.first == "!"
    }

    /// Strips URLs/emotes/@ (keeping the name), collapses whitespace, caps length so one troll can't hog the queue.
    static func sanitize(_ raw: String, maxLength: Int = 200) -> String {
        var s = raw
        for re in [SharedPatterns.url, SharedPatterns.kickEmote, SharedPatterns.colonEmote] {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = SharedPatterns.mention.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        s = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return s.count > maxLength ? String(s.prefix(maxLength)) : s
    }

    /// "one million toman", "ten euros", "five dollars and fifty cents"; other currencies as a plain number and code.
    static func spokenMoney(_ money: Money) -> String {
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
    static func spokenAmount(cents: Int) -> String {
        guard cents > 0 else { return "money" }
        let dollars = cents / 100
        guard cents % 100 == 0 else { return String(format: "%.2f dollars", Double(cents) / 100) }
        let f = NumberFormatter(); f.numberStyle = .spellOut
        let words = f.string(from: NSNumber(value: dollars)) ?? String(dollars)
        return "\(words) dollar\(dollars == 1 ? "" : "s")"
    }
}

extension ChatEvent {
    /// A slur or blocked word (Settings → Read aloud) in the name or text, or flagged by AI moderation:
    /// never read aloud and kept off the stream widgets.
    var offensive: Bool {
        if flagged { return true }
        let extra = UserDefaults.standard.string(forKey: "ttsBlocked") ?? ""
        return Speaker.isBlocked(user, extra: extra) || Speaker.isBlocked(text, extra: extra)
    }
}
