import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Catch me up": a 2-3 sentence on-device summary of recent chat. Nothing leaves the device.
@MainActor
enum ChatSummary {
    static let maxMessages = 60
    static let maxChars = 5000   // the on-device model has a small context window

    enum Failure: Error {
        case unavailable, empty, unsafe
        var message: String {
            switch self {
            case .unavailable: return "Apple Intelligence isn't available."
            case .empty: return "No recent English chat to summarize."
            case .unsafe: return "Couldn't summarize this chat."
            }
        }
    }

    /// "user: text" lines of the last `maxMessages` messages, minus blocked/flagged/non-Latin ones; newest kept if capped.
    static func transcript(_ events: [ChatEvent]) -> String {
        let lines = events.filter { $0.kind == .message && $0.origin != "test" && !$0.offensive }
            .suffix(maxMessages)
            .compactMap { e -> String? in
                let text = Speaker.sanitize(e.text, maxLength: 120)
                return ChatModeration.isMostlyLatin(text) ? "\(e.user): \(text)" : nil
            }
        return String(lines.joined(separator: "\n").suffix(maxChars))
    }

    static func summarize(_ events: [ChatEvent]) async throws -> String {
        guard ChatModerator.available else { throw Failure.unavailable }
        let chat = transcript(events)
        guard !chat.isEmpty else { throw Failure.empty }
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions:
            "Summarize live stream chat in 2 or 3 short, neutral sentences: the topics, the mood, anything asked of the streamer. "
            + "Never repeat insults or slurs.")
        let text: String
        do {
            text = try await session.respond(to: chat).content
        } catch let e as LanguageModelSession.GenerationError {
            if case .guardrailViolation = e { throw Failure.unsafe }
            throw e
        }
        // A summary may be spoken aloud, so it gets the same word list as everything else.
        let extra = UserDefaults.standard.string(forKey: "ttsBlocked") ?? ""
        if Speaker.isBlocked(text, extra: extra) { throw Failure.unsafe }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw Failure.unavailable
        #endif
    }
}
