import Foundation
import UIKit

/// Twitch Device Code Grant (public client, no secret), Helix channel reads/writes,
/// EventSub subscriptions, and hands-free broadcaster actions. State lives on Platforms.
@MainActor
final class TwitchService: ObservableObject {
    unowned let p: Platforms
    init(owner: Platforms) { p = owner }

    // Read scopes the chat feed's EventSub subscriptions need, keyed by the feature name the UI shows.
    // user:read:chat has shipped since the first Twitch connect, so old tokens already carry it; the other
    // three are new as of chat-feed support, so an existing user's token won't have them until they reconnect.
    static let chatScopes: [String: Set<String>] = [
        "chat": ["user:read:chat"],
        "follows": ["moderator:read:followers"],
        "subscriptions": ["channel:read:subscriptions"],
        "cheers": ["bits:read"],
    ]
    // Write scopes for hands-free broadcaster actions — the second and final re-auth milestone.
    // Same "reconnect once" pattern as chatScopes. Stream markers use channel:manage:broadcast, which
    // was already requested for title/category edits, so that action needs no new scope and has no
    // entry here — see createMarker.
    static let actionScopes: [String: Set<String>] = [
        "clips": ["clips:edit"],
        "ads": ["channel:read:ads", "channel:manage:ads"],
        "commercial": ["channel:edit:commercial"],
        "chat lockdown": ["moderator:manage:chat_settings"],
        "announcements": ["moderator:manage:announcements"],
        "raids": ["channel:manage:raids"],
        "moderation": ["moderator:manage:chat_messages", "moderator:manage:banned_users"],
    ]

    // https://dev.twitch.tv/docs/api/reference/#get-content-classification-labels — the current valid CCL ids.
    // Fallback set for when fetchLabelCatalog() hasn't run yet or failed.
    static let labelIDs = ["DebatedSocialIssuesAndPolitics", "DrugsIntoxication", "SexualThemes", "ViolentGraphic", "Gambling", "ProfanityVulgarity"]

    /// Pure scope-gap logic (no `self`), so it can be exercised without a live instance — see `demo()`.
    static func missingScopeFeatures(granted: Set<String>) -> [String] {
        chatScopes.merging(actionScopes) { a, _ in a }
            .filter { !$0.value.isSubset(of: granted) }.map(\.key).sorted()
    }

    #if DEBUG
    /// Self-check for the scope-gap logic: given a granted scope set, the right feature names come back
    /// as missing. This is the logic a user actually feels when a button is greyed out.
    static func demo() {
        let granted: Set<String> = ["channel:manage:broadcast", "user:read:chat", "clips:edit", "channel:read:ads", "channel:manage:ads"]
        let missing = missingScopeFeatures(granted: granted)
        let want = ["announcements", "chat lockdown", "cheers", "commercial", "follows", "moderation", "raids", "subscriptions"]
        assert(missing == want, "twitch scope-gap mismatch: got \(missing), want \(want)")
        assert(missingScopeFeatures(granted: []).count == chatScopes.count + actionScopes.count, "empty grant should miss every feature")
        applog("api", "TwitchService.demo: scope-gap check ok")
    }
    #endif

    private func api() -> PlatformEndpoint {
        PlatformEndpoint(base: "https://api.twitch.tv/helix", tokenKey: "twitchAccess",
            headers: ["Client-Id": PlatformConfig.twitchID], store: p.store) {
            let json = try await PlatformNet.form("https://id.twitch.tv/oauth2/token", [
                "grant_type": "refresh_token", "client_id": PlatformConfig.twitchID, "refresh_token": self.p.store.string(forKey: "twitchRefresh") ?? ""])
            if let scopes = try self.p.store.saveTokens(json, prefix: "twitch") { self.p.twitchScopes = Set(scopes) }
        }
    }

    func connect() {
        Task {
            do {
                let scopes = "channel:manage:broadcast channel:read:stream_key user:write:chat user:read:chat moderator:read:followers channel:read:subscriptions bits:read clips:edit channel:read:ads channel:manage:ads channel:edit:commercial moderator:manage:chat_settings moderator:manage:announcements channel:manage:raids moderator:manage:chat_messages moderator:manage:banned_users"
                let dev = try await PlatformNet.form("https://id.twitch.tv/oauth2/device", ["client_id": PlatformConfig.twitchID, "scopes": scopes])
                guard let deviceCode = dev["device_code"] as? String else { throw PlatformNet.err("no device_code: \(dev)") }
                p.twitchUserCode = dev["user_code"] as? String ?? ""
                p.twitchVerifyURL = dev["verification_uri"] as? String ?? "https://www.twitch.tv/activate"
                let interval = max(dev["interval"] as? Int ?? 5, 5)
                p.status = "Enter code \(p.twitchUserCode) on Twitch"
                if let u = URL(string: p.twitchVerifyURL) { await UIApplication.shared.open(u) }
                for _ in 0..<(900 / interval) {                        // ponytail: 15 min ceiling
                    try await Task.sleep(for: .seconds(interval))
                    let r = try await PlatformNet.form("https://id.twitch.tv/oauth2/token", [
                        "client_id": PlatformConfig.twitchID, "scopes": scopes, "device_code": deviceCode,
                        "grant_type": "urn:ietf:params:oauth:grant-type:device_code"], allowError: true)
                    if r["access_token"] != nil {
                        if let granted = try p.store.saveTokens(r, prefix: "twitch") { p.twitchScopes = Set(granted) }
                        p.twitchUserCode = ""
                        p.status = "Twitch connected"
                        await refresh()
                        return
                    }
                    if (r["message"] as? String) != "authorization_pending" { throw PlatformNet.err("Twitch: \(r["message"] ?? r)") }
                }
                p.status = "Twitch login timed out"
            } catch { p.status = error.localizedDescription; p.twitchUserCode = "" }
        }
    }

    func refresh() async {
        do {
            if let u = ((try await api().call("GET", "/users"))["data"] as? [[String: Any]])?.first {
                p.twitchUserID = u["id"] as? String ?? ""
                p.twitchUser = u["display_name"] as? String ?? u["login"] as? String ?? ""
            }
            let bid = [URLQueryItem(name: "broadcaster_id", value: p.twitchUserID)]
            if let ch = ((try await api().call("GET", "/channels", query: bid))["data"] as? [[String: Any]])?.first {
                p.twitchTitle = ch["title"] as? String ?? ""
                if let gid = ch["game_id"] as? String, !gid.isEmpty {
                    p.twitchCategory = StreamCategory(id: gid, name: ch["game_name"] as? String ?? "")
                }
                p.twitchTags = ch["tags"] as? [String] ?? []
                p.twitchLabels = Set(ch["content_classification_labels"] as? [String] ?? [])
                p.twitchDelay = ch["delay"] as? Int ?? 0
                p.twitchLanguage = ch["broadcaster_language"] as? String ?? ""
            }
            let live = ((try await api().call("GET", "/streams", query: [.init(name: "user_id", value: p.twitchUserID)]))["data"] as? [[String: Any]])?.first
            p.twitchLive = live != nil
            p.twitchViewers = live?["viewer_count"] as? Int ?? 0
            if let k = ((try await api().call("GET", "/streams/key", query: bid))["data"] as? [[String: Any]])?.first {
                p.twitchStreamKey = k["stream_key"] as? String ?? ""
            }
            if p.twitchHasScopes(["channel:read:ads"]) { await refreshAdSchedule() }
            p.status = "Twitch updated"
        } catch { p.status = error.localizedDescription }
    }

    func search(_ q: String) async -> [StreamCategory] {
        guard q.count >= 2 else { return [] }
        let r = try? await api().call("GET", "/search/categories", query: [.init(name: "query", value: q), .init(name: "first", value: "8")])
        return ((r?["data"] as? [[String: Any]]) ?? []).compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return StreamCategory(id: id, name: $0["name"] as? String ?? "")
        }
    }

    /// GET helix/content_classification_labels — the current, real label set with human names, so a label
    /// Twitch adds later shows up without a code change. Cached per session (guard on non-empty); left
    /// empty on any error, so callers fall back to labelIDs.
    func fetchLabelCatalog() async {
        guard p.twitchLabelCatalog.isEmpty else { return }
        guard let data = (try? await api().call("GET", "/content_classification_labels"))?["data"] as? [[String: Any]] else { return }
        let parsed = data.compactMap { item -> (id: String, name: String)? in
            guard let id = item["id"] as? String else { return nil }
            return (id, (item["name"] as? String) ?? (item["description"] as? String) ?? id)
        }
        guard !parsed.isEmpty else { return }
        p.twitchLabelCatalog = parsed
    }

    /// `tags`/`labels`/`delay`/`language` are all "omit when unchanged" against the last-loaded values, so an
    /// untouched (or not-yet-loaded) field can never silently wipe what's already on the channel.
    func apply(title: String, category: StreamCategory?, tags: [String] = [], labels: [String: Bool] = [:], delay: Int = 0, language: String = "") async {
        var body: [String: Any] = ["title": title]
        if let category { body["game_id"] = category.id }

        // ponytail: drop invalid tags instead of 400ing — no spaces, ≤25 chars, ≤10 tags (Twitch's own limits).
        let cleanTags = Array(tags.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains(" ") && $0.count <= 25 }.prefix(10))
        if cleanTags != p.twitchTags { body["tags"] = cleanTags }

        // Keyed off `labels`' own keys (whatever the view showed toggles for), not the hardcoded id list
        // directly, so a label the catalog added actually gets sent instead of silently staying as it was.
        let currentLabels = p.twitchLabels.intersection(labels.keys)
        let newLabels = Set(labels.filter(\.value).keys)
        if newLabels != currentLabels {
            body["content_classification_labels"] = labels.keys.map { ["id": $0, "is_enabled": newLabels.contains($0)] }
        }

        if delay != p.twitchDelay { body["delay"] = delay }   // Partner-only anti-stream-sniping delay
        let lang = language.trimmingCharacters(in: .whitespaces)
        if !lang.isEmpty, lang != p.twitchLanguage { body["broadcaster_language"] = lang }

        await PlatformFlow.mutate(status: { self.p.status = $0 }, done: "Twitch channel updated", refresh: { await self.refresh() }) {
            _ = try await self.api().call("PATCH", "/channels", query: [.init(name: "broadcaster_id", value: self.p.twitchUserID)], body: body)
        }
    }

    func send(_ text: String) async {
        await PlatformFlow.attempt(status: { self.p.status = $0 }) {
            _ = try await self.api().call("POST", "/chat/messages", body: ["broadcaster_id": self.p.twitchUserID, "sender_id": self.p.twitchUserID, "message": text])
        }
    }

    func disconnect() {
        p.store.forget("twitch")
        p.twitchUser = ""; p.twitchTitle = ""; p.twitchCategory = nil; p.twitchStreamKey = ""
        p.twitchTags = []; p.twitchLabels = []; p.twitchDelay = 0; p.twitchLanguage = ""; p.twitchScopes = []
        p.twitchAdNextAt = nil; p.twitchAdSnoozeCount = 0
    }

    /// Subscribes one Twitch EventSub WebSocket session to everything `ChatFeed` speaks. Types/versions/
    /// conditions per Twitch's EventSub subscription types reference. A type whose scope is missing is
    /// skipped, not attempted — `twitchMissingScopeFeatures` is the one place that explains the gap.
    func subscribeEventSub(sessionID: String) async {
        guard !p.twitchUserID.isEmpty else { applog("chat", "twitch eventsub subscribe skipped: no user id yet", error: true); return }
        let transport: [String: Any] = ["method": "websocket", "session_id": sessionID]
        var subs: [(type: String, version: String, condition: [String: String])] = [
            ("channel.raid", "1", ["to_broadcaster_user_id": p.twitchUserID]),
        ]
        if p.twitchHasScopes(["user:read:chat"]) { subs.append(("channel.chat.message", "1", ["broadcaster_user_id": p.twitchUserID, "user_id": p.twitchUserID])) }
        if p.twitchHasScopes(["moderator:read:followers"]) { subs.append(("channel.follow", "2", ["broadcaster_user_id": p.twitchUserID, "moderator_user_id": p.twitchUserID])) }
        if p.twitchHasScopes(["channel:read:subscriptions"]) { subs.append(("channel.subscribe", "1", ["broadcaster_user_id": p.twitchUserID])) }
        if p.twitchHasScopes(["bits:read"]) { subs.append(("channel.cheer", "1", ["broadcaster_user_id": p.twitchUserID])) }
        for s in subs {
            do {
                _ = try await api().call("POST", "/eventsub/subscriptions", body: ["type": s.type, "version": s.version, "condition": s.condition, "transport": transport])
            } catch {
                applog("chat", "twitch eventsub subscribe \(s.type) failed: \(error.localizedDescription)", error: true)
            }
        }
    }

    /// POST helix/clips, scope clips:edit. Twitch creates the clip asynchronously — the id/url come back
    /// immediately but the clip itself can take a few seconds to finish processing on Twitch's side.
    struct TwitchClip { let id: String; let url: String }
    func createClip() async throws -> TwitchClip {
        guard !p.twitchUserID.isEmpty else { throw PlatformNet.err("twitch: not connected") }
        let r = try await api().call("POST", "/clips", query: [.init(name: "broadcaster_id", value: p.twitchUserID)])
        guard let c = (r["data"] as? [[String: Any]])?.first, let id = c["id"] as? String else { throw PlatformNet.err("twitch: clip create returned no id") }
        return TwitchClip(id: id, url: "https://clips.twitch.tv/\(id)")
    }

    /// POST helix/streams/markers — body key is `user_id`, not `broadcaster_id` (Twitch's own inconsistency).
    /// Scope channel:manage:broadcast, already requested for title/category edits, so no new grant needed.
    func createMarker() async throws {
        guard !p.twitchUserID.isEmpty else { throw PlatformNet.err("twitch: not connected") }
        _ = try await api().call("POST", "/streams/markers", body: ["user_id": p.twitchUserID])
    }

    /// GET helix/channels/ads, scope channel:read:ads. `next_ad_at` is "" when nothing is scheduled.
    /// Failures are logged, not surfaced — a quiet countdown beats spamming errors.
    func refreshAdSchedule() async {
        do {
            guard let a = ((try await api().call("GET", "/channels/ads", query: [.init(name: "broadcaster_id", value: p.twitchUserID)]))["data"] as? [[String: Any]])?.first else { return }
            p.twitchAdSnoozeCount = a["snooze_count"] as? Int ?? 0
            if let s = a["next_ad_at"] as? String, !s.isEmpty { p.twitchAdNextAt = ISO8601DateFormatter().date(from: s) } else { p.twitchAdNextAt = nil }
        } catch { applog("api", "twitch ad schedule: \(error.localizedDescription)", error: true) }
    }

    /// POST helix/channels/ads/schedule/snooze, scope channel:manage:ads.
    func snoozeAd() async {
        await PlatformFlow.mutate(status: { self.p.status = $0 }, done: "Ad snoozed", refresh: { await self.refreshAdSchedule() }) {
            _ = try await self.api().call("POST", "/channels/ads/schedule/snooze", query: [.init(name: "broadcaster_id", value: self.p.twitchUserID)])
        }
    }

    /// POST helix/channels/commercial, scope channel:edit:commercial. Twitch only accepts
    /// 30/60/90/120/150/180s. ponytail: fixed 90s, no length picker — that needs the screen.
    func startCommercial(seconds: Int = 90) async {
        guard !p.twitchUserID.isEmpty else { return }
        await PlatformFlow.attempt(status: { self.p.status = $0 }) {
            _ = try await self.api().call("POST", "/channels/commercial", body: ["broadcaster_id": self.p.twitchUserID, "length": seconds])
            self.p.status = "Commercial started"
        }
    }

    /// PATCH helix/chat/settings, scope moderator:manage:chat_settings. `moderator_id` = the broadcaster
    /// themself. ponytail: fixed 10-min follower gate / 10s slow mode, no duration tuning UI.
    func lockdownChat(on: Bool) async {
        guard !p.twitchUserID.isEmpty else { return }
        let body: [String: Any] = on
            ? ["follower_mode": true, "follower_mode_duration_minutes": 10, "slow_mode": true, "slow_mode_wait_seconds": 10]
            : ["follower_mode": false, "slow_mode": false]
        await PlatformFlow.attempt(status: { self.p.status = $0 }) {
            _ = try await self.api().call("PATCH", "/chat/settings", query: self.modQuery, body: body)
            self.p.status = on ? "Chat locked down" : "Chat lockdown lifted"
        }
    }

    /// POST helix/chat/announcements, scope moderator:manage:announcements. ponytail: always
    /// default ("primary") color — a color picker is a screen-attention feature this app doesn't need.
    func announce(_ message: String) async {
        let m = message.trimmingCharacters(in: .whitespaces)
        guard !p.twitchUserID.isEmpty, !m.isEmpty else { return }
        await PlatformFlow.attempt(status: { self.p.status = $0 }) {
            _ = try await self.api().call("POST", "/chat/announcements", query: self.modQuery, body: ["message": m])
            self.p.status = "Announcement sent"
        }
    }

    /// POST helix/raids, scope channel:manage:raids. Takes a login name (what a user would type/say),
    /// resolves it to an id via GET /users first.
    func raid(_ targetLogin: String) async {
        let login = targetLogin.trimmingCharacters(in: .whitespaces).lowercased()
        guard !p.twitchUserID.isEmpty, !login.isEmpty else { return }
        do {
            guard let toID = ((try await api().call("GET", "/users", query: [.init(name: "login", value: login)]))["data"] as? [[String: Any]])?.first?["id"] as? String else {
                p.status = "Twitch: no user named \(login)"; return
            }
            _ = try await api().call("POST", "/raids", query: [.init(name: "from_broadcaster_id", value: p.twitchUserID), .init(name: "to_broadcaster_id", value: toID)])
            p.status = "Raiding \(login)"
        } catch { p.status = error.localizedDescription }
    }

    /// `broadcaster_id` + `moderator_id` query pair every moderator-scoped Helix call needs; the
    /// broadcaster is always allowed to moderate their own channel, so moderator_id = twitchUserID.
    private var modQuery: [URLQueryItem] { [.init(name: "broadcaster_id", value: p.twitchUserID), .init(name: "moderator_id", value: p.twitchUserID)] }
}
