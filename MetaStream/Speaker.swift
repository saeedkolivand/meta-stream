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
    }

    // MARK: Chat lane + templated alerts (tip/follow/subscribe/raid)

    func speak(_ event: ChatEvent) {
        guard var text = sentence(for: event) else { return }   // mute is enforced in enqueue(_:into:)
        if showOrigin, !event.origin.isEmpty { text = "on \(event.origin), " + text }
        switch event.kind {
        case .message: enqueue(text, into: &chatQueue)
        default: enqueue(text, into: &alertQueue)
        }
    }

    private func sentence(for e: ChatEvent) -> String? {
        switch e.kind {
        case .message:
            guard messagesOn else { return nil }
            let text = Self.sanitize(e.text)
            guard !text.isEmpty else { return nil }
            return "\(e.user) says \(text)"
        case .tip:
            guard tipsOn, e.amountCents >= minTipCents else { return nil }
            let amount = Self.spokenAmount(cents: e.amountCents)
            let note = Self.sanitize(e.text)
            return note.isEmpty ? "\(e.user) tipped \(amount)" : "\(e.user) tipped \(amount): \(note)"
        case .follow:
            return followsOn ? "\(e.user) followed" : nil
        case .subscribe:
            return subsOn ? "\(e.user) subscribed" : nil
        case .cheer:
            guard tipsOn else { return nil }   // bits are money; same gate as tips
            let note = Self.sanitize(e.text)
            return note.isEmpty ? "\(e.user) cheered \(e.count) bits" : "\(e.user) cheered \(e.count) bits: \(note)"
        case .raid:
            return raidsOn ? "\(e.user) raided with \(e.count) viewers" : nil
        }
    }

    private func enqueue(_ text: String, into queue: inout [String]) {
        guard !muted else { return }
        pushBounded(text, into: &queue)
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
        if !voiceID.isEmpty { u.voice = AVSpeechSynthesisVoice(identifier: voiceID) }
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

