import AuthenticationServices
import CoreLogging
import CoreStorage
import CryptoKit
import Foundation
import Observation
import os
import UIKit

/// Kick, Twitch, Restream, YouTube accounts: login, channel info (title/category/viewers), chat send, stream key.
/// Thin facade: all observed state lives here (the views' source of truth) and every behavior
/// delegates to the services in Platforms/ (Kick/Twitch/Restream/YouTubeService + PlatformCore).
/// ponytail: tokens live in UserDefaults; move to Keychain if the phone is shared.
@MainActor @Observable
public final class Platforms: NSObject {
    public var status = "" { didSet { applog("api", "status: \(status)") } }

    // Kick
    public var kickUser = ""
    public var kickTitle = ""
    public var kickCategory: StreamCategory?
    public var kickLive = false
    public var kickViewers = 0
    public var kickStreamURL = ""
    public var kickStreamKey = ""
    public var kickTags: [String] = []
    public var kickUserID = 0

    // Twitch
    public var twitchUser = ""
    public var twitchTitle = ""
    public var twitchCategory: StreamCategory?
    public var twitchLive = false
    public var twitchViewers = 0
    public var twitchStreamKey = ""
    public var twitchUserCode = ""
    public var twitchVerifyURL = ""
    public var twitchTags: [String] = []
    public var twitchLabels: Set<String> = []
    public var twitchDelay = 0
    public var twitchLanguage = ""
    public var twitchScopes: Set<String> = []
    public var twitchAdNextAt: Date?
    public var twitchAdSnoozeCount = 0
    /// Fetched from an authenticated helix/users call. Readable so Emotes can ask 7TV/BTTV/FFZ for this
    /// channel's sets without going round Twitch's undocumented web GQL for an ID we already hold.
    public var twitchUserID = ""
    public var twitchLabelCatalog: [(id: String, name: String)] = []

    // Restream
    public var restreamUser = ""
    public var restreamDestinations: [RestreamDestination] = []
    public var restreamTitle = ""
    public var restreamStreamKey = ""
    public var restreamChatURL = ""

    // YouTube
    public var ytUser = ""
    public var ytTitle = ""
    public var ytDescription = ""
    public var ytPrivacy = "public"
    public var ytLatency = "normal"
    public var ytLive = false
    public var ytViewers = 0
    public var ytVideoID = ""
    public var ytStreamKey = ""
    public var ytIngest = "rtmps://a.rtmps.youtube.com:443/live2"
    public var ytLiveChatID = ""
    public var ytBroadcast: [String: Any] = [:]

    public let store: TokenStore = UserDefaults.standard
    public let auth = AuthPresenter()

    @ObservationIgnored private(set) lazy var kick = KickService(owner: self)
    @ObservationIgnored private(set) lazy var twitch = TwitchService(owner: self)
    @ObservationIgnored private(set) lazy var restream = RestreamService(owner: self)
    @ObservationIgnored private(set) lazy var youTube = YouTubeService(owner: self)

    // Config compat (single source of truth in PlatformConfig).
    public static var webRedirect: String { PlatformConfig.webRedirect }
    public static var googleRedirect: String { PlatformConfig.googleRedirect }
    public static var kickIngest: String { PlatformConfig.kickIngest }
    public static var twitchIngest: String { PlatformConfig.twitchIngest }
    public static var restreamIngest: String { PlatformConfig.restreamIngest }
    public static var hasRestreamApp: Bool { !PlatformConfig.restreamID.isEmpty }
    public static var hasYouTubeApp: Bool { !PlatformConfig.youtubeID.isEmpty }

    // Twitch scope tables compat (single source of truth in TwitchService; covered by PlatformsTests).
    public static var twitchChatScopes: [String: Set<String>] { TwitchService.chatScopes }
    public static var twitchActionScopes: [String: Set<String>] { TwitchService.actionScopes }
    public static var twitchLabelIDs: [String] { TwitchService.labelIDs }
    public static func missingScopeFeatures(granted: Set<String>) -> [String] { TwitchService.missingScopeFeatures(granted: granted) }

    public typealias TwitchClip = TwitchService.TwitchClip

    // Tokens live in the store, which Observation can't see: reading status and the user name too keeps views that show
    // "connected" refreshing when a connect or disconnect flow updates them (as ObservableObject's blanket refresh did).
    public var kickConnected: Bool { _ = (status, kickUser); return store.string(forKey: "kickAccess") != nil }
    public var twitchConnected: Bool { _ = (status, twitchUser); return store.string(forKey: "twitchAccess") != nil }
    public var restreamConnected: Bool { _ = (status, restreamUser); return store.string(forKey: "restreamAccess") != nil }
    public var ytConnected: Bool { _ = (status, ytUser); return store.string(forKey: "ytAccess") != nil }

    public override init() {
        super.init()
        twitchScopes = Set(store.stringArray(forKey: "twitchScopes") ?? [])
        if kickConnected { Task { await refreshKick() } }
        if twitchConnected { Task { await refreshTwitch() } }
        if restreamConnected { Task { await refreshRestream() } }
        if ytConnected { Task { await refreshYouTube() } }
    }

    /// While a stream session runs, viewer counts are re-read every 60 s (both platforms update theirs about once a
    /// minute): the viewer pill, {viewers} and anything else reading kickViewers/twitchViewers. Ends when the task is
    /// cancelled (ContentView keys it on streamer.live). FOUND BUG: counts used to be fetched only at launch and in the
    /// Stream Manager, so a 7 h stream showed its go-live number throughout.
    public func pollViewersWhileLive() async {
        while !Task.isCancelled {
            if kickConnected { await kick.refreshViewers() }
            if twitchConnected { await twitch.refreshViewers() }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    // MARK: - Kick

    public func connectKick() { kick.connect() }
    public func refreshKick() async { await kick.refresh() }
    public func kickSearch(_ q: String) async -> [StreamCategory] { await kick.search(q) }
    public func kickApply(title: String, category: StreamCategory?, tags: [String] = []) async {
        await kick.apply(title: title, category: category, tags: tags)
    }
    public func kickSend(_ text: String) async { await kick.send(text) }
    public func disconnectKick() { kick.disconnect() }

    // MARK: - Twitch

    public func connectTwitch() { twitch.connect() }
    public func refreshTwitch() async { await twitch.refresh() }
    public func twitchSearch(_ q: String) async -> [StreamCategory] { await twitch.search(q) }
    public func fetchTwitchLabelCatalog() async { await twitch.fetchLabelCatalog() }
    public func twitchApply(title: String, category: StreamCategory?, tags: [String] = [], labels: [String: Bool] = [:], delay: Int = 0, language: String = "") async {
        await twitch.apply(title: title, category: category, tags: tags, labels: labels, delay: delay, language: language)
    }
    public func twitchSend(_ text: String) async { await twitch.send(text) }
    public func disconnectTwitch() { twitch.disconnect() }

    /// True when every scope in `required` was granted at the last Twitch auth.
    public func twitchHasScopes(_ required: Set<String>) -> Bool { required.isSubset(of: twitchScopes) }

    /// Feature names whose scope is missing from the granted set — empty once the user reconnects.
    public var twitchMissingScopeFeatures: [String] { TwitchService.missingScopeFeatures(granted: twitchScopes) }

    public func twitchSubscribeEventSub(sessionID: String) async { await twitch.subscribeEventSub(sessionID: sessionID) }
    public func twitchCreateClip() async throws -> TwitchClip { try await twitch.createClip() }
    public func twitchCreateMarker() async throws { try await twitch.createMarker() }
    public func twitchRefreshAdSchedule() async { await twitch.refreshAdSchedule() }
    public func twitchSnoozeAd() async { await twitch.snoozeAd() }
    public func twitchStartCommercial(seconds: Int = 90) async { await twitch.startCommercial(seconds: seconds) }
    public func twitchLockdownChat(on: Bool) async { await twitch.lockdownChat(on: on) }
    public func twitchAnnounce(_ message: String) async { await twitch.announce(message) }
    public func twitchRaid(_ targetLogin: String) async { await twitch.raid(targetLogin) }

    // MARK: - Restream

    public func connectRestream() { restream.connect() }
    public func refreshRestream() async { await restream.refresh() }
    public func restreamApply(title: String) async { await restream.apply(title: title) }
    public func restreamSetActive(_ ch: RestreamDestination, _ on: Bool) async { await restream.setActive(ch, on) }
    public func disconnectRestream() { restream.disconnect() }

    // MARK: - YouTube

    public func connectYouTube() { youTube.connect() }
    public func refreshYouTube() async { await youTube.refresh() }
    public func ytApply(title: String, description: String, privacy: String, latency: String) async {
        await youTube.apply(title: title, description: description, privacy: privacy, latency: latency)
    }
    public func ytSend(_ text: String) async { await youTube.send(text) }
    public func disconnectYouTube() { youTube.disconnect() }
    public func ytPollLiveChat(pageToken: String?) async throws -> (items: [[String: Any]], nextPageToken: String?, pollingIntervalMillis: Int)? {
        try await youTube.pollLiveChat(pageToken: pageToken)
    }
}
