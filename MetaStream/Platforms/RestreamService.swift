import Foundation

/// Restream OAuth 2 code flow (Basic-auth token exchange, no PKCE offered), channel list,
/// per-destination titles, and stream key. State lives on Platforms.
@MainActor
final class RestreamService: ObservableObject {
    unowned let p: Platforms
    init(owner: Platforms) { p = owner }

    private func api() -> PlatformEndpoint {
        PlatformEndpoint(base: "https://api.restream.io/v2", tokenKey: "restreamAccess", headers: [:], store: p.store) {
            let json = try await PlatformNet.form("https://api.restream.io/oauth/token",
                ["grant_type": "refresh_token", "refresh_token": self.p.store.string(forKey: "restreamRefresh") ?? ""],
                basic: (PlatformConfig.restreamID, PlatformConfig.restreamSecret))
            try self.p.store.saveTokens(json, prefix: "restream")
        }
    }

    func connect() {
        Task {
            var c = URLComponents(string: "https://api.restream.io/login")!
            c.queryItems = [
                .init(name: "response_type", value: "code"), .init(name: "client_id", value: PlatformConfig.restreamID),
                .init(name: "redirect_uri", value: PlatformConfig.webRedirect), .init(name: "state", value: PlatformNet.random(16)),
            ]
            await PlatformFlow.codeFlow(name: "Restream", authURL: c.url!, scheme: "metastream",
                authorize: p.auth.authorize,
                exchange: { code in try await PlatformNet.form("https://api.restream.io/oauth/token",
                    ["grant_type": "authorization_code", "redirect_uri": PlatformConfig.webRedirect, "code": code],
                    basic: (PlatformConfig.restreamID, PlatformConfig.restreamSecret)) },
                prefix: "restream", store: p.store,
                status: { self.p.status = $0 },
                after: { await self.refresh() })
        }
    }

    func refresh() async {
        do {
            if let pr = try await api().callAny("GET", "/user/profile") as? [String: Any] { p.restreamUser = pr["username"] as? String ?? "" }
            // The list comes back wrapped: {"channels":[...]}; older docs show a bare array, so accept both.
            let raw = try await api().callAny("GET", "/user/channels")
            let list = (raw as? [[String: Any]]) ?? ((raw as? [String: Any])?["channels"] as? [[String: Any]]) ?? []
            // The list omits the on/off state, so ask each channel for it. Two or three calls, once per refresh.
            var channels: [RestreamDestination] = []
            for c in list {
                guard let id = c["id"] as? Int else { continue }
                let detail = (try? await api().callAny("GET", "/user/channels/\(id)")) as? [String: Any] ?? [:]
                let on = detail["active"] as? Bool ?? detail["enabled"] as? Bool ?? true
                channels.append(RestreamDestination(id: id, name: c["displayName"] as? String ?? "channel \(id)",
                                                url: c["channelUrl"] as? String ?? "", active: on))
            }
            p.restreamDestinations = channels
            if let first = p.restreamDestinations.first, let m = try await api().callAny("GET", "/user/channel-meta/\(first.id)") as? [String: Any] {
                p.restreamTitle = m["title"] as? String ?? ""
            }
            if let k = try await api().callAny("GET", "/user/streamKey") as? [String: Any] { p.restreamStreamKey = k["streamKey"] as? String ?? "" }
            if let c = try await api().callAny("GET", "/user/webchat/url") as? [String: Any] { p.restreamChatURL = c["webchatUrl"] as? String ?? "" }
            p.status = "Restream updated"
        } catch { p.status = error.localizedDescription }
    }

    /// One title for every destination Restream fans out to.
    func apply(title: String) async {
        await PlatformFlow.mutate(status: { self.p.status = $0 }, done: "Restream titles updated", refresh: { await self.refresh() }) {
            for ch in self.p.restreamDestinations { _ = try await self.api().callAny("PATCH", "/user/channel-meta/\(ch.id)", body: ["title": title]) }
        }
    }

    /// Enables or disables one destination. Restream documents the update under the singular path; some
    /// deployments answer on the plural one, so try both before reporting failure.
    func setActive(_ ch: RestreamDestination, _ on: Bool) async {
        func apply() { if let i = p.restreamDestinations.firstIndex(where: { $0.id == ch.id }) { p.restreamDestinations[i].active = on } }
        do {
            _ = try await api().callAny("PATCH", "/user/channel/\(ch.id)", body: ["active": on])
            apply(); p.status = "\(ch.name) \(on ? "enabled" : "disabled")"
        } catch {
            do {
                _ = try await api().callAny("PATCH", "/user/channels/\(ch.id)", body: ["active": on])
                apply(); p.status = "\(ch.name) \(on ? "enabled" : "disabled")"
            } catch { p.status = error.localizedDescription }
        }
    }

    func disconnect() {
        p.store.forget("restream")
        p.restreamUser = ""; p.restreamDestinations = []; p.restreamTitle = ""; p.restreamStreamKey = ""; p.restreamChatURL = ""
    }
}
