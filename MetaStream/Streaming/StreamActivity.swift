// Lock Screen / Dynamic Island intents: compiled into BOTH the app and the MetaStreamLiveActivity widget extension
// (App Intents metadata is extracted per binary, so these can't live in the ActivityShared package target, which
// holds the attributes). Keep this file free of anything app-only (Streamer, HaishinKit...).
import AppIntents
import Foundation
import Platforms

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
