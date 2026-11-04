import CoreLogging
import CoreNetwork
import CoreStorage
import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

public struct StreamCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
public struct RestreamDestination: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let url: String
    public var active: Bool

    public init(id: Int, name: String, url: String, active: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.active = active
    }
}

// MARK: - PlatformConfig

/// Client IDs/secrets (from Info.plist), OAuth redirects, and ingest URLs in one place.
public enum PlatformConfig {
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    public static let kickID = info["KickClientID"] as? String ?? ""
    public static let kickSecret = info["KickClientSecret"] as? String ?? ""
    public static let twitchID = info["TwitchClientID"] as? String ?? ""
    public static let restreamID = info["RestreamClientID"] as? String ?? ""
    public static let restreamSecret = info["RestreamClientSecret"] as? String ?? ""
    public static let youtubeID = info["YouTubeClientID"] as? String ?? ""
    public static let webRedirect = "https://metastream.iamsaeed.dev/oauth.html"
    public static let googleRedirect = "com.saeedkolivand.metastream:/oauth2redirect"
    public static let kickIngest = "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/"
    public static let twitchIngest = "rtmps://live.twitch.tv:443/app/"
    public static let restreamIngest = "rtmp://live.restream.io/live"
}

// MARK: - AuthPresenter

/// Owns the ASWebAuthenticationSession. One instance lives on Platforms; services borrow it.
@MainActor
public final class AuthPresenter: NSObject {
    private var session: ASWebAuthenticationSession?
    private let contextProvider = AuthContextProvider()

    /// Opens the system auth sheet and hands back the `code` query item (nil if cancelled).
    public func authorize(_ url: URL, scheme: String) async -> String? {
        await withCheckedContinuation { cont in
            applog("auth", "authorize \(url.host ?? "?")\(url.path) scheme=\(scheme)")
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
                let code = items.first(where: { $0.name == "code" })?.value
                applog("auth", "callback url=\(url?.host ?? "nil")\(url?.path ?? "") params=\(items.map(\.name)) code=\(code == nil ? "missing" : "ok") error=\(error.map { String(describing: $0) } ?? "none")", error: code == nil)
                cont.resume(returning: code)
            }
            s.presentationContextProvider = contextProvider
            session = s
            s.start()
        }
    }
}

/// NSObject trampoline: the presentation-anchor protocol method is nonisolated.
private final class AuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let w = scenes.compactMap(\.keyWindow).first { return w }
            guard let scene = scenes.first else { preconditionFailure("no window scene to present sign-in") }
            return ASPresentationAnchor(windowScene: scene)
        }
    }
}

// MARK: - PlatformFlow

/// Shared skeletons behind the three OAuth-code connects and the apply/send methods.
public enum PlatformFlow {
    /// Authorize → token exchange → persist → status → refresh. `name` fills the status strings.
    @MainActor public static func codeFlow(name: String, authURL: URL, scheme: String,
        authorize: @MainActor (URL, String) async -> String?,
        exchange: @MainActor (String) async throws -> [String: Any],
        prefix: String, store: TokenStore,
        status: @MainActor (String) -> Void,
        after: @MainActor () async -> Void) async {
        guard let code = await authorize(authURL, scheme) else { status("\(name) login cancelled"); return }
        do {
            let json = try await exchange(code)
            try store.saveTokens(json, prefix: prefix)
            status("\(name) connected")
            await after()
        } catch { status("\(name) token error: \(error.localizedDescription)") }
    }

    /// Fire-and-forget mutation (chat send): only failures surface.
    @MainActor public static func attempt(status: @MainActor (String) -> Void, work: @MainActor () async throws -> Void) async {
        do { try await work() } catch { status(error.localizedDescription) }
    }

    /// Apply-style mutation: work, success status, then re-fetch.
    @MainActor public static func mutate(status: @MainActor (String) -> Void, done: String, refresh: @MainActor () async -> Void, work: @MainActor () async throws -> Void) async {
        do { try await work(); status(done); await refresh() } catch { status(error.localizedDescription) }
    }
}
