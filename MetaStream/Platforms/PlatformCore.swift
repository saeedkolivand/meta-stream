import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

struct StreamCategory: Identifiable, Hashable { let id: String; let name: String }
struct RestreamDestination: Identifiable, Hashable { let id: Int; let name: String; let url: String; var active: Bool }

// MARK: - TokenStore

/// UserDefaults-shaped token persistence behind a protocol so services never touch Platforms internals.
protocol TokenStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    func stringArray(forKey key: String) -> [String]?
}

extension UserDefaults: TokenStore {}

extension TokenStore {
    /// Persists access/refresh tokens; returns the granted scope list when the provider sends one.
    /// Only Twitch sends `scope` as an array, and only Twitch's token can carry fewer scopes than
    /// requested, so only Twitch callers need the return value.
    @discardableResult
    func saveTokens(_ json: [String: Any], prefix: String) throws -> [String]? {
        guard let access = json["access_token"] as? String else { throw PlatformNet.err("no access_token in \(json)") }
        set(access, forKey: prefix + "Access")
        if let r = json["refresh_token"] as? String { set(r, forKey: prefix + "Refresh") }
        if let scopes = json["scope"] as? [String] {
            set(scopes, forKey: prefix + "Scopes")
            return scopes
        }
        return nil
    }

    func forget(_ prefix: String) {
        [prefix + "Access", prefix + "Refresh", prefix + "Scopes"].forEach { removeObject(forKey: $0) }
    }
}

// MARK: - PlatformConfig

/// Client IDs/secrets (from Info.plist), OAuth redirects, and ingest URLs in one place.
enum PlatformConfig {
    private static let info = Bundle.main.infoDictionary ?? [:]
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

// MARK: - PlatformNet

enum PlatformNet {
    /// POST application/x-www-form-urlencoded → JSON object. Non-2xx throws unless allowError (device-flow polling).
    static func form(_ url: String, _ fields: [String: String], allowError: Bool = false, basic: (String, String)? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let (u, p) = basic { req.setValue("Basic " + Data("\(u):\(p)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization") }
        var c = URLComponents(); c.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = c.percentEncodedQuery?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        applog("auth", "POST \(url) [\(fields.keys.sorted().joined(separator: ","))] -> \(code) \(code < 300 ? "ok" : redact(String(decoding: data.prefix(400), as: UTF8.self)))", error: code >= 400)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard allowError || (200..<300).contains(code) else { throw err("HTTP \(code): \(String(data: data, encoding: .utf8) ?? "")") }
        return json
    }

    static func s256(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func random(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }

    static func err(_ s: String) -> NSError { applog("api", "error: \(s)", error: true); return NSError(domain: "Platforms", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }
}

// MARK: - PlatformEndpoint

/// The single authenticated-API factory. Replaces the four per-platform wrappers
/// (kick/helix/restream/yt): each service builds one with its base URL, token key,
/// extra headers, and refresh closure.
@MainActor
struct PlatformEndpoint {
    let base: String
    let tokenKey: String
    let headers: [String: String]
    let store: TokenStore
    let refresh: @MainActor () async throws -> Void

    /// Authenticated JSON-object call with one token refresh + retry on 401.
    func call(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> [String: Any] {
        try await callAny(method, path, query: query, body: body) as? [String: Any] ?? [:]
    }

    func callAny(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil, retried: Bool = false) async throws -> Any {
        var c = URLComponents(string: base + path)!
        if !query.isEmpty { c.queryItems = query }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.setValue("Bearer \(store.string(forKey: tokenKey) ?? "")", forHTTPHeaderField: "Authorization")
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        applog("api", "\(method) \(c.url!.absoluteString) -> \(code) \(redact(String(decoding: data.prefix(700), as: UTF8.self)))", error: code >= 400)
        if code == 401, !retried {
            try await refresh()
            return try await callAny(method, path, query: query, body: body, retried: true)
        }
        guard (200..<300).contains(code) else { throw PlatformNet.err("\((base + path).split(separator: "/").suffix(2).joined(separator: "/")) → HTTP \(code): \(String(data: data, encoding: .utf8) ?? "")") }
        return data.isEmpty ? [:] : ((try? JSONSerialization.jsonObject(with: data)) ?? [:])
    }
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
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
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
