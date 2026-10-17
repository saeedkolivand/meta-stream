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
        var commands: [LockCommand] = []   // up to 3 saved chat commands shown as buttons (Settings > Chat commands)
    }
}

struct LockCommand: Codable, Hashable {
    var id: String           // BotCommand.id.uuidString
    var text: String
}

/// What the Lock Screen / Dynamic Island buttons trigger. LiveActivityIntent.perform() runs in the APP
/// process, but the intents below are also compiled into the extension (Button(intent:) needs the type),
/// where Streamer does not exist, so the app registers the real actions here at launch.
@MainActor
enum StreamActivityActions {
    // ponytail: shared statics instead of dependency injection; one Streamer per process, set once in attach().
    static var stop: (@MainActor () -> Void)?
    static var toggleMute: (@MainActor () -> Void)?
    static var sendCommand: (@MainActor (String) -> Void)?   // set in App.swift (needs Platforms)
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

struct SendCommandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Send chat command"
    @Parameter(title: "Command ID") var commandID: String
    init() {}
    init(commandID: String) { self.commandID = commandID }
    func perform() async throws -> some IntentResult {
        await MainActor.run { StreamActivityActions.sendCommand?(commandID) }
        return .result()
    }
}
