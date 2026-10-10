// Live Activity contract: compiled into BOTH the app and the MetaStreamLiveActivity widget extension.
// The widget renders ContentState; the app owns the Activity (LiveActivity.swift). Keep this file free of
// anything app-only (Streamer, HaishinKit...) or the extension target will not build.
import ActivityKit
import AppIntents
import Foundation

struct StreamActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String        // "live" | "reconnecting" | "ended"
        var liveSince: Date      // the widget ticks a timer from this, so no per-second updates are needed
        var kbps: Int
        var source: String       // Streamer.source: "phone" | "glasses" | "back" ...
        var drops: Int
        var muted: Bool
        var endedAt: Date?       // set only with phase "ended", so the lingering card shows the final duration
    }
}

/// What the Lock Screen / Dynamic Island buttons trigger. LiveActivityIntent.perform() runs in the APP
/// process, but the intents below are also compiled into the extension (Button(intent:) needs the type),
/// where Streamer does not exist, so the app registers the real actions here at launch.
@MainActor
enum StreamActivityActions {
    // ponytail: shared statics instead of dependency injection; one Streamer per process, set once in attach().
    static var stop: (@MainActor () -> Void)?
    static var toggleMute: (@MainActor () -> Void)?
}

struct StopStreamIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop stream"
    func perform() async throws -> some IntentResult {
        await MainActor.run { StreamActivityActions.stop?() }
        return .result()
    }
}

struct ToggleMuteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mute or unmute mic"
    func perform() async throws -> some IntentResult {
        await MainActor.run { StreamActivityActions.toggleMute?() }
        return .result()
    }
}
