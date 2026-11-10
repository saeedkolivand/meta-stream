import CoreLogging
import CoreStorage
import CryptoKit
import Foundation

// MARK: - TokenStore helpers

extension TokenStore {
    /// Persists access/refresh tokens; returns the granted scope list when the provider sends one.
    /// Only Twitch sends `scope` as an array, and only Twitch's token can carry fewer scopes than
    /// requested, so only Twitch callers need the return value.
    @discardableResult
    public func saveTokens(_ json: [String: Any], prefix: String) throws -> [String]? {
        guard let access = json["access_token"] as? String else { throw PlatformNet.err("no access_token in \(json)") }
        set(access, forKey: prefix + "Access")
        if let refresh = json["refresh_token"] as? String { set(refresh, forKey: prefix + "Refresh") }
        if let scopes = json["scope"] as? [String] {
            set(scopes, forKey: prefix + "Scopes")
            return scopes
        }
        return nil
    }

    public func forget(_ prefix: String) {
        [prefix + "Access", prefix + "Refresh", prefix + "Scopes"].forEach { removeObject(forKey: $0) }
    }
}

// MARK: - PlatformNet

/// Unauthenticated calls (OAuth token endpoints), PKCE, and the one error type.
public enum PlatformNet {
    /// POST application/x-www-form-urlencoded → JSON object. Non-2xx throws unless allowError (device-flow polling).
    public static func form(
        _ url: String, _ fields: [String: String], allowError: Bool = false
    ) async throws -> [String: Any] {
        guard let target = URL(string: url) else { throw err("bad URL \(url)") }
        var req = URLRequest(url: target)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let detail = code < 300 ? "ok" : redact(String(decoding: data.prefix(400), as: UTF8.self))
        applog("auth", "POST \(url) [\(fields.keys.sorted().joined(separator: ","))] -> \(code) \(detail)", error: code >= 400)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard allowError || (200..<300).contains(code) else { throw err("HTTP \(code): \(String(decoding: data, as: UTF8.self))") }
        return json
    }

    public static func s256(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func random(_ count: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<count).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    /// A request that failed because iOS paused the app (the user went to Safari to enter a login code) or the network
    /// blinked: a login poll retries these instead of giving up.
    public static func isTransient(_ error: Error) -> Bool {
        guard let url = error as? URLError else { return false }
        return [.cancelled, .networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotConnectToHost].contains(url.code)
    }

    public static func err(_ message: String) -> NSError {
        applog("api", "error: \(message)", error: true)
        return NSError(domain: "Platforms", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - PlatformEndpoint

/// The single authenticated-API factory. Replaces the four per-platform wrappers
/// (kick/helix/restream/yt): each service builds one with its base URL, token key,
/// extra headers, and refresh closure.
@MainActor
public struct PlatformEndpoint {
    let base: String
    let tokenKey: String
    let headers: [String: String]
    let store: TokenStore
    let refresh: @MainActor () async throws -> Void

    public init(
        base: String, tokenKey: String, headers: [String: String], store: TokenStore,
        refresh: @escaping @MainActor () async throws -> Void
    ) {
        self.base = base
        self.tokenKey = tokenKey
        self.headers = headers
        self.store = store
        self.refresh = refresh
    }

    /// Authenticated JSON-object call with one token refresh + retry on 401.
    public func call(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> [String: Any] {
        try await callAny(method, path, query: query, body: body) as? [String: Any] ?? [:]
    }

    public func callAny(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil, retried: Bool = false
    ) async throws -> Any {
        guard var parts = URLComponents(string: base + path) else { throw PlatformNet.err("bad URL \(base + path)") }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw PlatformNet.err("bad URL \(base + path)") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(store.string(forKey: tokenKey) ?? "")", forHTTPHeaderField: "Authorization")
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let reply = redact(String(decoding: data.prefix(700), as: UTF8.self))
        applog("api", "\(method) \(url.absoluteString) -> \(code) \(reply)", error: code >= 400)
        if code == 401, !retried {
            try await refresh()
            return try await callAny(method, path, query: query, body: body, retried: true)
        }
        guard (200..<300).contains(code) else {
            let name = (base + path).split(separator: "/").suffix(2).joined(separator: "/")
            throw PlatformNet.err("\(name) → HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
        return data.isEmpty ? [:] : ((try? JSONSerialization.jsonObject(with: data)) ?? [:])
    }
}
