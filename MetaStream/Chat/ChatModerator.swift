import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The pure decisions behind AI moderation, split out so they can be unit-tested without a model.
@MainActor
enum ChatModeration {
    static let maxWaiting = 8                    // more than this queued = chat flood
    static let holdLimit: Duration = .milliseconds(1500)

    /// True if most letters are Latin script (the on-device model only handles those languages well; Persian etc. fall
    /// back to the word list). Latin = Basic Latin through Latin Extended-B plus Latin Extended Additional.
    nonisolated static func isMostlyLatin(_ s: String) -> Bool {
        var letters = 0, latin = 0
        for u in s.unicodeScalars where u.properties.isAlphabetic {
            letters += 1
            if u.value < 0x250 || (0x1E00...0x1EFF).contains(u.value) { latin += 1 }
        }
        return letters >= 3 && latin * 10 >= letters * 7
    }

    /// ponytail: overflow rule - past maxWaiting the extra messages skip the AI and go straight through; a flood can't
    /// be reviewed in time anyway and the word list still applies.
    static func shouldHold(waiting: Int) -> Bool { waiting < maxWaiting }

    /// The text to classify, or nil if the event needn't be reviewed: not a chat message, the flood test, already caught
    /// by the word list, or not Latin script.
    static func reviewText(for e: ChatEvent) -> String? {
        guard e.kind == .message, e.origin != "test", !e.offensive else { return nil }
        let text = Speaker.sanitize(e.text, maxLength: 300)   // no URLs/emotes: fewer tokens, less noise
        return isMostlyLatin(text) ? text : nil
    }
}

/// Holds each chat message briefly while Apple's on-device model classifies it (like Twitch AutoMod), then hands it on
/// with `flagged` set if unsafe. Without Apple Intelligence (or the toggle off) `review` delivers synchronously.
@MainActor
final class ChatModerator {
    typealias Deliver = @MainActor (ChatEvent) -> Void
    private var waiting = 0
    private var tail: Task<Void, Never>?   // serial: each review awaits the previous one

    static var available: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static var enabled: Bool {
        (UserDefaults.standard.object(forKey: "aiModeration") as? Bool ?? true) && available
    }

    func review(_ e: ChatEvent, deliver: @escaping Deliver) {
        guard Self.enabled, let text = ChatModeration.reviewText(for: e), ChatModeration.shouldHold(waiting: waiting) else {
            return deliver(e)
        }
        waiting += 1
        // ponytail: 1.5 s cap measured from arrival, so a slow model delays chat by at most that, never accumulates.
        let deadline = ContinuousClock.now + ChatModeration.holdLimit
        let prev = tail
        tail = Task { [weak self] in
            await prev?.value
            guard let self else { return deliver(e) }
            var out = e
            if await Self.isUnsafe(text, until: deadline) {
                out.flagged = true
                applog("chat", "AI moderation hid a message from \(e.origin)")
            }
            waiting -= 1
            deliver(out)
        }
    }

    /// True if the model calls `text` unsafe. Fails open (false) on timeout or any error but a guardrail violation.
    /// A race with a resume-once continuation, not a task group: a group waits for every child, so a model call that
    /// ignores cancellation would hold chat past the deadline.
    /// ponytail: a timed-out call keeps running in the background; under a flood several can overlap (capped by maxWaiting).
    private static func isUnsafe(_ text: String, until deadline: ContinuousClock.Instant) async -> Bool {
        #if canImport(FoundationModels)
        guard ContinuousClock.now < deadline else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(c)
            Task { @MainActor in once.resume(await ask(text)) }
            Task { @MainActor in
                try? await Task.sleep(for: deadline - ContinuousClock.now)
                once.resume(false)
            }
        }
        #else
        return false
        #endif
    }
}

/// Resumes a continuation with the first value only.
@MainActor
private final class ResumeOnce {
    private var c: CheckedContinuation<Bool, Never>?
    init(_ c: CheckedContinuation<Bool, Never>) { self.c = c }
    func resume(_ v: Bool) {
        c?.resume(returning: v)
        c = nil
    }
}

#if canImport(FoundationModels)
@Generable
private struct ChatVerdict {
    @Guide(description: "true if the message is hateful, harassing, sexual, threatening, or encourages self-harm")
    var isUnsafe: Bool
}

private func ask(_ text: String) async -> Bool {
    do {
        // A fresh session per message: the verdicts are independent and a shared transcript would fill the context window.
        let session = LanguageModelSession(instructions: "You moderate a live stream chat. Judge only the message you are given.")
        return try await session.respond(to: text, generating: ChatVerdict.self).content.isUnsafe
    } catch let e as LanguageModelSession.GenerationError {
        // The model's own safety filter fired on the input: treat as unsafe.
        if case .guardrailViolation = e { return true }
        applog("chat", "AI moderation error (letting through)")
        return false
    } catch {
        applog("chat", "AI moderation error (letting through)")
        return false
    }
}
#endif
