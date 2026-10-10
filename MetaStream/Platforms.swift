import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import os

/// Kick, Twitch, Restream, YouTube accounts: login, channel info (title/category/viewers), chat send, stream key.
/// Thin facade: all @Published state lives here (the views' source of truth) and every behavior
/// delegates to the services in Platforms/ (Kick/Twitch/Restream/YouTubeService + PlatformCore).
/// ponytail: tokens live in UserDefaults; move to Keychain if the phone is shared.
@MainActor
final class Platforms: NSObject, ObservableObject {
    @Published var status = "" { didSet { applog("api", "status: \(status)") } }

    // Kick
    @Published var kickUser = ""
    @Published var kickTitle = ""
    @Published var kickCategory: StreamCategory?
    @Published var kickLive = false
    @Published var kickViewers = 0
    @Published var kickStreamURL = ""
    @Published var kickStreamKey = ""
    @Published var kickTags: [String] = []
    var kickUserID = 0

    // Twitch
    @Published var twitchUser = ""
    @Published var twitchTitle = ""
    @Published var twitchCategory: StreamCategory?
    @Published var twitchLive = false
    @Published var twitchViewers = 0
    @Published var twitchStreamKey = ""
    @Published var twitchUserCode = ""
    @Published var twitchVerifyURL = ""
    @Published var twitchTags: [String] = []
    @Published var twitchLabels: Set<String> = []
    @Published var twitchDelay = 0
    @Published var twitchLanguage = ""
    @Published var twitchScopes: Set<String> = []
    @Published var twitchAdNextAt: Date?
    @Published var twitchAdSnoozeCount = 0
    /// Fetched from an authenticated helix/users call. Readable so Emotes can ask 7TV/BTTV/FFZ for this
    /// channel's sets without going round Twitch's undocumented web GQL for an ID we already hold.
    var twitchUserID = ""
    @Published var twitchLabelCatalog: [(id: String, name: String)] = []

    // Restream
    @Published var restreamUser = ""
    @Published var restreamDestinations: [RestreamDestination] = []
    @Published var restreamTitle = ""
    @Published var restreamStreamKey = ""
    @Published var restreamChatURL = ""

    // YouTube
    @Published var ytUser = ""
    @Published var ytTitle = ""
    @Published var ytDescription = ""
    @Published var ytPrivacy = "public"
    @Published var ytLatency = "normal"
    @Published var ytLive = false
    @Published var ytViewers = 0
    @Published var ytVideoID = ""
    @Published var ytStreamKey = ""
    @Published var ytIngest = "rtmps://a.rtmps.youtube.com:443/live2"
    var ytLiveChatID = ""
    var ytBroadcast: [String: Any] = [:]

    let store: TokenStore = UserDefaults.standard
    let auth = AuthPresenter()

    private(set) lazy var kick = KickService(owner: self)
    private(set) lazy var twitch = TwitchService(owner: self)
    private(set) lazy var restream = RestreamService(owner: self)
    private(set) lazy var youTube = YouTubeService(owner: self)

    // Config compat (single source of truth in PlatformConfig).
    static var webRedirect: String { PlatformConfig.webRedirect }
    static var googleRedirect: String { PlatformConfig.googleRedirect }
    static var kickIngest: String { PlatformConfig.kickIngest }
    static var twitchIngest: String { PlatformConfig.twitchIngest }
    static var restreamIngest: String { PlatformConfig.restreamIngest }
    static var hasRestreamApp: Bool { !PlatformConfig.restreamID.isEmpty }
    static var hasYouTubeApp: Bool { !PlatformConfig.youtubeID.isEmpty }

    // Twitch scope tables compat (single source of truth in TwitchService; covered by PlatformsTests).
    static var twitchChatScopes: [String: Set<String>] { TwitchService.chatScopes }
    static var twitchActionScopes: [String: Set<String>] { TwitchService.actionScopes }
    static var twitchLabelIDs: [String] { TwitchService.labelIDs }
    static func missingScopeFeatures(granted: Set<String>) -> [String] { TwitchService.missingScopeFeatures(granted: granted) }

    typealias TwitchClip = TwitchService.TwitchClip

    var kickConnected: Bool { store.string(forKey: "kickAccess") != nil }
    var twitchConnected: Bool { store.string(forKey: "twitchAccess") != nil }
    var restreamConnected: Bool { store.string(forKey: "restreamAccess") != nil }
    var ytConnected: Bool { store.string(forKey: "ytAccess") != nil }

    override init() {
        super.init()
        twitchScopes = Set(store.stringArray(forKey: "twitchScopes") ?? [])
        if kickConnected { Task { await refreshKick() } }
        if twitchConnected { Task { await refreshTwitch() } }
        if restreamConnected { Task { await refreshRestream() } }
        if ytConnected { Task { await refreshYouTube() } }
    }

    // MARK: - Kick

    func connectKick() { kick.connect() }
    func refreshKick() async { await kick.refresh() }
    func kickSearch(_ q: String) async -> [StreamCategory] { await kick.search(q) }
    func kickApply(title: String, category: StreamCategory?, tags: [String] = []) async {
        await kick.apply(title: title, category: category, tags: tags)
    }
    func kickSend(_ text: String) async { await kick.send(text) }
    func disconnectKick() { kick.disconnect() }

    // MARK: - Twitch

    func connectTwitch() { twitch.connect() }
    func refreshTwitch() async { await twitch.refresh() }
    func twitchSearch(_ q: String) async -> [StreamCategory] { await twitch.search(q) }
    func fetchTwitchLabelCatalog() async { await twitch.fetchLabelCatalog() }
    func twitchApply(title: String, category: StreamCategory?, tags: [String] = [], labels: [String: Bool] = [:], delay: Int = 0, language: String = "") async {
        await twitch.apply(title: title, category: category, tags: tags, labels: labels, delay: delay, language: language)
    }
    func twitchSend(_ text: String) async { await twitch.send(text) }
    func disconnectTwitch() { twitch.disconnect() }

    /// True when every scope in `required` was granted at the last Twitch auth.
    func twitchHasScopes(_ required: Set<String>) -> Bool { required.isSubset(of: twitchScopes) }

    /// Feature names whose scope is missing from the granted set — empty once the user reconnects.
    var twitchMissingScopeFeatures: [String] { TwitchService.missingScopeFeatures(granted: twitchScopes) }

    func twitchSubscribeEventSub(sessionID: String) async { await twitch.subscribeEventSub(sessionID: sessionID) }
    func twitchCreateClip() async throws -> TwitchClip { try await twitch.createClip() }
    func twitchCreateMarker() async throws { try await twitch.createMarker() }
    func twitchRefreshAdSchedule() async { await twitch.refreshAdSchedule() }
    func twitchSnoozeAd() async { await twitch.snoozeAd() }
    func twitchStartCommercial(seconds: Int = 90) async { await twitch.startCommercial(seconds: seconds) }
    func twitchLockdownChat(on: Bool) async { await twitch.lockdownChat(on: on) }
    func twitchAnnounce(_ message: String) async { await twitch.announce(message) }
    func twitchRaid(_ targetLogin: String) async { await twitch.raid(targetLogin) }

    // MARK: - Restream

    func connectRestream() { restream.connect() }
    func refreshRestream() async { await restream.refresh() }
    func restreamApply(title: String) async { await restream.apply(title: title) }
    func restreamSetActive(_ ch: RestreamDestination, _ on: Bool) async { await restream.setActive(ch, on) }
    func disconnectRestream() { restream.disconnect() }

    // MARK: - YouTube

    func connectYouTube() { youTube.connect() }
    func refreshYouTube() async { await youTube.refresh() }
    func ytApply(title: String, description: String, privacy: String, latency: String) async {
        await youTube.apply(title: title, description: description, privacy: privacy, latency: latency)
    }
    func ytSend(_ text: String) async { await youTube.send(text) }
    func disconnectYouTube() { youTube.disconnect() }
    func ytPollLiveChat(pageToken: String?) async throws -> (items: [[String: Any]], nextPageToken: String?, pollingIntervalMillis: Int)? {
        try await youTube.pollLiveChat(pageToken: pageToken)
    }
}
