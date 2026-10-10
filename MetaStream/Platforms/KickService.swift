import Foundation

/// Kick OAuth 2.1 + PKCE, channel info, chat send. State lives on Platforms (the views'
/// source of truth); this service only mutates it, so existing callers keep working.
@MainActor
final class KickService: ObservableObject {
    unowned let p: Platforms
    init(owner: Platforms) { p = owner }

    private func api() -> PlatformEndpoint {
        PlatformEndpoint(base: "https://api.kick.com", tokenKey: "kickAccess", headers: [:], store: p.store) {
            let json = try await PlatformNet.form("https://id.kick.com/oauth/token", [
                "grant_type": "refresh_token", "client_id": PlatformConfig.kickID, "client_secret": PlatformConfig.kickSecret,
                "refresh_token": self.p.store.string(forKey: "kickRefresh") ?? ""])
            try self.p.store.saveTokens(json, prefix: "kick")
        }
    }

    func connect() {
        Task {
            let verifier = PlatformNet.random(64)
            var c = URLComponents(string: "https://id.kick.com/oauth/authorize")!
            c.queryItems = [
                .init(name: "response_type", value: "code"), .init(name: "client_id", value: PlatformConfig.kickID),
                .init(name: "redirect_uri", value: PlatformConfig.webRedirect),
                .init(name: "scope", value: "user:read channel:read channel:write chat:write streamkey:read"),
                .init(name: "code_challenge", value: PlatformNet.s256(verifier)), .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: PlatformNet.random(16)),
            ]
            await PlatformFlow.codeFlow(name: "Kick", authURL: c.url!, scheme: "metastream",
                authorize: p.auth.authorize,
                exchange: { code in try await PlatformNet.form("https://id.kick.com/oauth/token", [
                    "grant_type": "authorization_code", "client_id": PlatformConfig.kickID, "client_secret": PlatformConfig.kickSecret,
                    "redirect_uri": PlatformConfig.webRedirect, "code_verifier": verifier, "code": code]) },
                prefix: "kick", store: p.store,
                status: { self.p.status = $0 },
                after: { await self.refresh() })
        }
    }

    func refresh() async {
        do {
            if let u = ((try await api().call("GET", "/public/v1/users"))["data"] as? [[String: Any]])?.first {
                p.kickUserID = u["user_id"] as? Int ?? 0
                p.kickUser = u["name"] as? String ?? ""
            }
            if let ch = ((try await api().call("GET", "/public/v1/channels"))["data"] as? [[String: Any]])?.first {
                p.kickTitle = ch["stream_title"] as? String ?? ""
                if let cat = ch["category"] as? [String: Any], let id = cat["id"] as? Int {
                    p.kickCategory = StreamCategory(id: String(id), name: cat["name"] as? String ?? "")
                }
                let st = ch["stream"] as? [String: Any] ?? [:]
                p.kickLive = st["is_live"] as? Bool ?? false
                p.kickViewers = st["viewer_count"] as? Int ?? 0
                p.kickStreamKey = st["key"] as? String ?? ""
                p.kickStreamURL = st["url"] as? String ?? ""
                if p.kickUser.isEmpty { p.kickUser = ch["slug"] as? String ?? "" }
            }
            p.status = "Kick updated"
        } catch { p.status = error.localizedDescription }
    }

    func search(_ q: String) async -> [StreamCategory] {
        guard q.count >= 3 else { return [] }
        let r = try? await api().call("GET", "/public/v2/categories", query: [.init(name: "name", value: q), .init(name: "limit", value: "8")])
        return ((r?["data"] as? [[String: Any]]) ?? []).compactMap {
            guard let id = $0["id"] as? Int else { return nil }
            return StreamCategory(id: String(id), name: $0["name"] as? String ?? "")
        }
    }

    func apply(title: String, category: StreamCategory?, tags: [String] = []) async {
        var body: [String: Any] = ["stream_title": title]
        if let category, let id = Int(category.id) { body["category_id"] = id }
        let cleanTags = Array(tags.prefix(10))                          // Kick caps custom_tags at 10
        if cleanTags != p.kickTags { body["custom_tags"] = cleanTags }  // omit when unchanged: an empty/unloaded field must not wipe real tags
        await PlatformFlow.mutate(status: { self.p.status = $0 }, done: "Kick title updated", refresh: { await self.refresh() }) {
            _ = try await self.api().call("PATCH", "/public/v1/channels", body: body)
            if body["custom_tags"] != nil { self.p.kickTags = cleanTags }
        }
    }

    func send(_ text: String) async {
        await PlatformFlow.attempt(status: { self.p.status = $0 }) {
            _ = try await self.api().call("POST", "/public/v1/chat", body: ["content": text, "type": "user", "broadcaster_user_id": self.p.kickUserID])
        }
    }

    func disconnect() {
        p.store.forget("kick")
        p.kickUser = ""; p.kickTitle = ""; p.kickCategory = nil; p.kickStreamKey = ""; p.kickTags = []
    }
}
