import Foundation

/// A real problem found in the current settings, and the page that fixes it.
struct SettingsIssue: Identifiable {
    let pageID: String
    let message: String
    var id: String { pageID + message }
}

/// What the "Ready to go live" card shows. Every check reads state the app really has (connection flags, the donation
/// hub's own status text, saved keys), never a guess about the network.
@MainActor
enum SettingsReadiness {
    private static let defaults = UserDefaults.standard

    static func chips(_ ctx: SettingsContext) -> [String] {
        var mic = SettingsValues.audio(ctx)
        if mic == "Default" { mic = "Default mic" } else if mic.isEmpty { mic = "Microphone" }
        return [SettingsValues.ingest(), SettingsValues.quality(ctx), mic, SettingsValues.camera(ctx)].filter { !$0.isEmpty }
    }

    static func issues(_ ctx: SettingsContext) -> [SettingsIssue] {
        destination(ctx) + donations() + telegram() + bots(ctx) + remote()
    }

    /// The ingest platform's account isn't connected (Kick/Twitch/YouTube/Restream), or a manual destination has no key.
    private static func destination(_ ctx: SettingsContext) -> [SettingsIssue] {
        let platform = defaults.string(forKey: "platform") ?? "kick"
        if let adapter = PlatformAdapter.all[platform] {
            guard adapter.hasApp, !adapter.connected(ctx.platforms) else { return [] }
            return [SettingsIssue(pageID: "accounts", message: "\(adapter.name) is not connected")]
        }
        guard (defaults.string(forKey: "streamKey") ?? "").isEmpty else { return [] }
        return [SettingsIssue(pageID: "ingest", message: "No stream key for the destination")]
    }

    /// A donation site with a saved key whose own status says the key was rejected or the site can't be reached.
    private static func donations() -> [SettingsIssue] {
        let hub = DonationHub.shared
        return DonationHub.Site.allCases.compactMap { site in
            guard !hub.key(site).isEmpty, let status = hub.status[site] else { return nil }
            guard status.hasPrefix("Key rejected") || status.hasPrefix("Can't reach") else { return nil }
            return SettingsIssue(pageID: "sources", message: "\(site.title): \(status.components(separatedBy: " ·")[0])")
        }
    }

    private static func telegram() -> [SettingsIssue] {
        guard defaults.bool(forKey: "telegramOn"), (defaults.string(forKey: "telegramChannel") ?? "").isEmpty else { return [] }
        return [SettingsIssue(pageID: "telegram", message: "Telegram live post has no channel")]
    }

    private static func bots(_ ctx: SettingsContext) -> [SettingsIssue] {
        guard defaults.bool(forKey: "botTwitch") else { return [] }
        // The bot reads your chat through YOUR Twitch login and posts into your channel, so it needs both accounts.
        if !ctx.platforms.twitchConnected {
            return [SettingsIssue(pageID: "accounts", message: "App bot is on for Twitch but your Twitch account isn't connected")]
        }
        guard AppBot.shared.twitchBotName.isEmpty else { return [] }
        return [SettingsIssue(pageID: "accounts", message: "App bot is on for Twitch but has no bot account")]
    }

    private static func remote() -> [SettingsIssue] {
        guard defaults.bool(forKey: "obsServerOn"), (defaults.string(forKey: "obsPassword") ?? "").count < 8 else { return [] }
        return [SettingsIssue(pageID: "remote", message: "Remote control password is shorter than 8 characters")]
    }
}
