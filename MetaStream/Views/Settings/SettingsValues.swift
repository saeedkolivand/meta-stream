import Foundation

/// The grey summaries on the settings rows. Each reads the same UserDefaults key (and default) as the screen it
/// summarises; empty means "nothing worth saying", never a guess.
@MainActor
enum SettingsValues {
    private static let defaults = UserDefaults.standard
    private static let platformNames = ["kick": "Kick", "twitch": "Twitch", "youtube": "YouTube", "restream": "Restream",
                                        "instagram": "Instagram", "tiktok": "TikTok", "custom": "Custom"]
    private static let glassesVideo = ["low": "360×640", "medium": "504×896", "high": "720×1280"]

    private static func onOff(_ key: String, _ fallback: Bool = false) -> String {
        (defaults.object(forKey: key) as? Bool ?? fallback) ? "On" : "Off"
    }

    // MARK: Stream

    static func accounts(_ ctx: SettingsContext) -> String {
        let count = PlatformAdapter.all.values.filter { $0.connected(ctx.platforms) }.count
        return count == 0 ? "" : "\(count) connected"
    }

    /// "Kick · RTMPS": the ingest platform and the protocol its URL uses.
    static func ingest() -> String {
        let platform = platformNames[defaults.string(forKey: "platform") ?? "kick"] ?? ""
        let url = (defaults.string(forKey: "rtmpURL") ?? "rtmps://").lowercased()
        let protocols = ["srtla://": "SRTLA", "srt://": "SRT", "rtmps://": "RTMPS", "rtmp://": "RTMP"]
        let proto = protocols.first { url.hasPrefix($0.key) }?.value ?? ""
        return [platform, proto].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func camera(_ ctx: SettingsContext) -> String {
        if ctx.streamer.manualSource == "external", let name = ctx.streamer.externalCameraName { return name }
        return defaults.string(forKey: "fallbackCamera") == "front" ? "Front" : "Back"
    }

    static func glasses() -> String { onOff("glassesEnabled") }

    /// The picked microphone's name; "Default" when none is picked, empty when the picked one isn't plugged in.
    static func audio(_ ctx: SettingsContext) -> String {
        let uid = defaults.string(forKey: "micUID") ?? ""
        if uid.isEmpty { return "Default" }
        return ctx.streamer.mics.first { $0.id == uid }?.name ?? ""
    }

    static func privacy() -> String { onOff("blurOn") }

    /// "720p · 30 fps" for the phone camera, "720×1280 · 30 fps" when the glasses are the source.
    static func quality(_ ctx: SettingsContext) -> String {
        let source = ctx.streamer.manualSource
        if Streamer.glassesEnabled, source == "glasses" || source == "auto" {
            let size = glassesVideo[defaults.string(forKey: "resolution") ?? "high"] ?? ""
            let fps = defaults.object(forKey: "fps") as? Int ?? 30
            return "\(size) · \(fps) fps"
        }
        let height = defaults.object(forKey: "phoneHeight") as? Int ?? 720
        let fps = defaults.object(forKey: "phoneFps") as? Int ?? 30
        return "\(height)p · \(fps) fps"
    }

    // MARK: On screen, chat

    static func scenes() -> String {
        let count = OverlayStore.shared.scenes.count
        return count == 0 ? "" : "\(count) scene" + (count == 1 ? "" : "s")
    }

    static func theme() -> String { ColorTheme(rawValue: defaults.string(forKey: "colorTheme") ?? "")?.name ?? "" }

    static func chat() -> String {
        let origin = defaults.string(forKey: "chatOrigin") == "twitch" ? "Twitch" : "Kick"
        let channel = defaults.string(forKey: "chatChannel") ?? ""
        return channel.isEmpty ? "" : origin + " · " + channel
    }

    static func commands() -> String {
        let count = BotCommand.decode(defaults.string(forKey: "botCommands") ?? BotCommand.seed).count
        return count == 0 ? "" : "\(count)"
    }

    static func appBot() -> String {
        let on = [("botKick", "Kick"), ("botTwitch", "Twitch")].filter { defaults.bool(forKey: $0.0) }.map(\.1)
        return on.isEmpty ? "Off" : on.joined(separator: ", ")
    }

    // MARK: Money, reach, system

    /// "€120 / €500", in the goal's own currency.
    static func goal() -> String {
        let goal = GoalStore.shared
        let currency = goal.config.currency
        return Money(goal.total, currency).display + " / " + Money(goal.config.target, currency).display
    }

    static func sources() -> String {
        let count = DonationHub.Site.allCases.filter { !DonationHub.shared.key($0).isEmpty }.count
        return count == 0 ? "" : "\(count) set up"
    }

    static func telegram() -> String { onOff("telegramOn") }

    static func spotify() -> String { SpotifyNowPlaying.shared.connected ? "Connected" : "" }

    static func remote() -> String { onOff("obsServerOn") }
}
