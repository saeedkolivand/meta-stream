import CoreLogging
import CoreNetwork
import CoreStorage
import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

struct StreamCategory: Identifiable, Hashable { let id: String; let name: String }
struct RestreamDestination: Identifiable, Hashable { let id: Int; let name: String; let url: String; var active: Bool }

// MARK: - PlatformConfig

/// Client IDs/secrets (from Info.plist), OAuth redirects, and ingest URLs in one place.
enum PlatformConfig {
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static let kickID = info["KickClientID"] as? String ?? ""
    static let kickSecret = info["KickClientSecret"] as? String ?? ""
    static let twitchID = info["TwitchClientID"] as? String ?? ""
    static let restreamID = info["RestreamClientID"] as? String ?? ""
    static let restreamSecret = info["RestreamClientSecret"] as? String ?? ""
    static let youtubeID = info["YouTubeClientID"] as? String ?? ""
    static let webRedirect = "https://metastream.iamsaeed.dev/oauth.html"
    static let googleRedirect = "com.saeedkolivand.metastream:/oauth2redirect"
    static let kickIngest = "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/"
    static let twitchIngest = "rtmps://live.twitch.tv:443/app/"
    static let restreamIngest = "rtmp://live.restream.io/live"
}

// MARK: - AuthPresenter

/// Owns the ASWebAuthenticationSession. One instance lives on Platforms; services borrow it.
@MainActor
final class AuthPresenter: NSObject {
    private var session: ASWebAuthenticationSession?
    private let contextProvider = AuthContextProvider()

    /// Opens the system auth sheet and hands back the `code` query item (nil if cancelled).
    func authorize(_ url: URL, scheme: String) async -> String? {
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
enum PlatformFlow {
    /// Authorize → token exchange → persist → status → refresh. `name` fills the status strings.
    @MainActor static func codeFlow(name: String, authURL: URL, scheme: String,
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
    @MainActor static func attempt(status: @MainActor (String) -> Void, work: @MainActor () async throws -> Void) async {
        do { try await work() } catch { status(error.localizedDescription) }
    }

    /// Apply-style mutation: work, success status, then re-fetch.
    @MainActor static func mutate(status: @MainActor (String) -> Void, done: String, refresh: @MainActor () async -> Void, work: @MainActor () async throws -> Void) async {
        do { try await work(); status(done); await refresh() } catch { status(error.localizedDescription) }
    }
}
