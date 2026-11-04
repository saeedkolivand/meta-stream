// Live Activity data contract between the app (which owns the Activity, LiveActivity.swift) and the
// MetaStreamLiveActivity widget extension (which renders ContentState). ActivityKit only.
// The intents behind the Lock Screen buttons stay in MetaStream/Streaming/StreamActivity.swift, compiled into both
// binaries: App Intents metadata is extracted per binary target, not from a static package.
import ActivityKit
import Foundation

public struct StreamActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: String        // "live" | "reconnecting" | "ended"
        public var liveSince: Date      // the widget ticks a timer from this, so no per-second updates are needed
        public var kbps: Int
        public var source: String       // Streamer.source: "phone" | "glasses" | "back" ...
        public var drops: Int
        public var muted: Bool
        public var endedAt: Date?       // set only with phase "ended", so the lingering card shows the final duration
        public var commands: [LockCommand]   // up to 3 saved chat commands shown as buttons (Settings > Chat commands)

        public init(
            phase: String, liveSince: Date, kbps: Int, source: String, drops: Int, muted: Bool, endedAt: Date? = nil,
            commands: [LockCommand] = []
        ) {
            self.phase = phase
            self.liveSince = liveSince
            self.kbps = kbps
            self.source = source
            self.drops = drops
            self.muted = muted
            self.endedAt = endedAt
            self.commands = commands
        }
    }

    public init() {}
}

public struct LockCommand: Codable, Hashable, Sendable {
    public var id: String           // BotCommand.id.uuidString
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}
