import Foundation

/// Uniform per-tab access to Platforms, keyed by tab id ("kick"/"twitch"/"restream"/"youtube").
/// Replaces the per-property switches (connected/user/isLive/viewers/streamKey/ingest) plus the
/// per-action switches (connect/refresh/disconnect/send/load/apply) with one dictionary lookup.
/// All closures are @MainActor: Platforms is @MainActor and views already touch it from the main thread.
public struct StreamInfoDraft: Sendable {
    public var title = ""
    public var category: StreamCategory?
    public var tags = ""
    public var labels: [String: Bool] = [:]
    public var delay = 0
    public var language = ""
    public var description = ""
    public var privacy = "public"
    public var latency = "normal"

    public init(
        title: String = "", category: StreamCategory? = nil, tags: String = "", labels: [String: Bool] = [:], delay: Int = 0,
        language: String = "", description: String = "", privacy: String = "public", latency: String = "normal"
    ) {
        self.title = title
        self.category = category
        self.tags = tags
        self.labels = labels
        self.delay = delay
        self.language = language
        self.description = description
        self.privacy = privacy
        self.latency = latency
    }
}

public struct PlatformAdapter {
    public let name: String
    public let hasApp: Bool
    public let hasCategory: Bool
    public let canSendChat: Bool
    public let connected: @MainActor (Platforms) -> Bool
    public let user: @MainActor (Platforms) -> String
    public let isLive: @MainActor (Platforms) -> Bool
    public let viewers: @MainActor (Platforms) -> Int
    public let streamKey: @MainActor (Platforms) -> String
    public let ingest: @MainActor (Platforms) -> String
    public let connect: @MainActor (Platforms) -> Void
    public let refresh: @MainActor (Platforms) async -> Void
    public let disconnect: @MainActor (Platforms) -> Void
    public let send: @MainActor (Platforms, String) async -> Void
    public let load: @MainActor (Platforms, [(id: String, name: String)]) -> StreamInfoDraft
    public let apply: @MainActor (Platforms, StreamInfoDraft) async -> Void

    @MainActor public static let all: [String: PlatformAdapter] = [
        "kick": PlatformAdapter(
            name: "Kick", hasApp: true, hasCategory: true, canSendChat: true,
            connected: { $0.kickConnected }, user: { $0.kickUser }, isLive: { $0.kickLive }, viewers: { $0.kickViewers },
            streamKey: { $0.kickStreamKey },
            ingest: { $0.kickStreamURL.isEmpty ? Platforms.kickIngest : $0.kickStreamURL },
            connect: { $0.connectKick() },
            refresh: { await $0.refreshKick() },
            disconnect: { $0.disconnectKick() },
            send: { await $0.kickSend($1) },
            load: { p, _ in StreamInfoDraft(title: p.kickTitle, category: p.kickCategory, tags: p.kickTags.joined(separator: ", ")) },
            apply: { p, d in await p.kickApply(title: d.title, category: d.category, tags: StreamInfoDraft.cleanTags(d.tags)) }
        ),
        "twitch": PlatformAdapter(
            name: "Twitch", hasApp: true, hasCategory: true, canSendChat: true,
            connected: { $0.twitchConnected }, user: { $0.twitchUser }, isLive: { $0.twitchLive }, viewers: { $0.twitchViewers },
            streamKey: { $0.twitchStreamKey },
            ingest: { _ in Platforms.twitchIngest },
            connect: { $0.connectTwitch() },
            refresh: {
                await $0.refreshTwitch()
                await $0.fetchTwitchLabelCatalog()
            },
            disconnect: { $0.disconnectTwitch() },
            send: { await $0.twitchSend($1) },
            load: { p, options in StreamInfoDraft(title: p.twitchTitle, category: p.twitchCategory,
                tags: p.twitchTags.joined(separator: ", "),
                labels: Dictionary(uniqueKeysWithValues: options.map { ($0.id, p.twitchLabels.contains($0.id)) }),
                delay: p.twitchDelay, language: p.twitchLanguage) },
            apply: { p, d in await p.twitchApply(title: d.title, category: d.category, tags: StreamInfoDraft.cleanTags(d.tags), labels: d.labels, delay: d.delay, language: d.language) }
        ),
        "restream": PlatformAdapter(
            name: "Restream", hasApp: Platforms.hasRestreamApp, hasCategory: false, canSendChat: false,
            connected: { $0.restreamConnected }, user: { $0.restreamUser }, isLive: { _ in false }, viewers: { _ in 0 },
            streamKey: { $0.restreamStreamKey },
            ingest: { _ in Platforms.restreamIngest },
            connect: { $0.connectRestream() },
            refresh: { await $0.refreshRestream() },
            disconnect: { $0.disconnectRestream() },
            send: { await $0.ytSend($1) },
            load: { p, _ in StreamInfoDraft(title: p.restreamTitle) },
            apply: { p, d in await p.restreamApply(title: d.title) }
        ),
        "youtube": PlatformAdapter(
            name: "YouTube", hasApp: Platforms.hasYouTubeApp, hasCategory: false, canSendChat: true,
            connected: { $0.ytConnected }, user: { $0.ytUser }, isLive: { $0.ytLive }, viewers: { $0.ytViewers },
            streamKey: { $0.ytStreamKey },
            ingest: { $0.ytIngest },
            connect: { $0.connectYouTube() },
            refresh: { await $0.refreshYouTube() },
            disconnect: { $0.disconnectYouTube() },
            send: { await $0.ytSend($1) },
            load: { p, _ in StreamInfoDraft(title: p.ytTitle, description: p.ytDescription, privacy: p.ytPrivacy, latency: p.ytLatency) },
            apply: { p, d in await p.ytApply(title: d.title, description: d.description, privacy: d.privacy, latency: d.latency) }
        ),
    ]

    public init(
        name: String,
        hasApp: Bool,
        hasCategory: Bool,
        canSendChat: Bool,
        connected: @escaping @MainActor (Platforms) -> Bool,
        user: @escaping @MainActor (Platforms) -> String,
        isLive: @escaping @MainActor (Platforms) -> Bool,
        viewers: @escaping @MainActor (Platforms) -> Int,
        streamKey: @escaping @MainActor (Platforms) -> String,
        ingest: @escaping @MainActor (Platforms) -> String,
        connect: @escaping @MainActor (Platforms) -> Void,
        refresh: @escaping @MainActor (Platforms) async -> Void,
        disconnect: @escaping @MainActor (Platforms) -> Void,
        send: @escaping @MainActor (Platforms, String) async -> Void,
        load: @escaping @MainActor (Platforms, [(id: String, name: String)]) -> StreamInfoDraft,
        apply: @escaping @MainActor (Platforms, StreamInfoDraft) async -> Void
    ) {
        self.name = name
        self.hasApp = hasApp
        self.hasCategory = hasCategory
        self.canSendChat = canSendChat
        self.connected = connected
        self.user = user
        self.isLive = isLive
        self.viewers = viewers
        self.streamKey = streamKey
        self.ingest = ingest
        self.connect = connect
        self.refresh = refresh
        self.disconnect = disconnect
        self.send = send
        self.load = load
        self.apply = apply
    }
}

extension StreamInfoDraft {
    public static func cleanTags(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
