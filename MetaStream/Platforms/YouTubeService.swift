import Foundation

/// YouTube Google OAuth for iOS (PKCE, no secret, bundle-id scheme redirect), broadcast
/// discovery, metadata apply, live-chat send/poll. State lives on Platforms.
@MainActor
final class YouTubeService: ObservableObject {
    unowned let p: Platforms
    init(owner: Platforms) { p = owner }

    private func api() -> PlatformEndpoint {
        PlatformEndpoint(base: "https://www.googleapis.com/youtube/v3", tokenKey: "ytAccess", headers: [:], store: p.store) {
            let json = try await PlatformNet.form("https://oauth2.googleapis.com/token", [
                "grant_type": "refresh_token", "client_id": PlatformConfig.youtubeID, "refresh_token": self.p.store.string(forKey: "ytRefresh") ?? ""])
            try self.p.store.saveTokens(json, prefix: "yt")
        }
    }

    func connect() {
        Task {
            let verifier = PlatformNet.random(64)
            var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            c.queryItems = [
                .init(name: "client_id", value: PlatformConfig.youtubeID), .init(name: "redirect_uri", value: PlatformConfig.googleRedirect),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: "https://www.googleapis.com/auth/youtube.force-ssl"),
                .init(name: "code_challenge", value: PlatformNet.s256(verifier)), .init(name: "code_challenge_method", value: "S256"),
                .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
            ]
            await PlatformFlow.codeFlow(name: "YouTube", authURL: c.url!, scheme: "com.saeedkolivand.metastream",
                authorize: p.auth.authorize,
                exchange: { code in try await PlatformNet.form("https://oauth2.googleapis.com/token", [
                    "client_id": PlatformConfig.youtubeID, "code": code, "code_verifier": verifier,
                    "grant_type": "authorization_code", "redirect_uri": PlatformConfig.googleRedirect]) },
                prefix: "yt", store: p.store,
                status: { self.p.status = $0 },
                after: { await self.refresh() })
        }
    }

    func refresh() async {
        do {
            if let ch = ((try await api().call("GET", "/channels", query: [.init(name: "part", value: "snippet"), .init(name: "mine", value: "true")]))["items"] as? [[String: Any]])?.first {
                p.ytUser = (ch["snippet"] as? [String: Any])?["title"] as? String ?? ""
            }
            let items = (try await api().call("GET", "/liveBroadcasts", query: [
                .init(name: "part", value: "id,snippet,contentDetails,status"), .init(name: "mine", value: "true"), .init(name: "maxResults", value: "10")]))["items"] as? [[String: Any]] ?? []
            let preferred = ["live", "liveStarting", "testing", "ready", "created"]
            // The broadcast YouTube Studio calls "your stream": the most alive one, else the newest.
            let pick = preferred.lazy.compactMap { s in items.first { (($0["status"] as? [String: Any])?["lifeCycleStatus"] as? String) == s } }.first ?? items.first
            if let b = pick {
                p.ytBroadcast = b
                p.ytVideoID = b["id"] as? String ?? ""
                let sn = b["snippet"] as? [String: Any] ?? [:]
                p.ytTitle = sn["title"] as? String ?? ""
                p.ytDescription = sn["description"] as? String ?? ""
                p.ytLiveChatID = sn["liveChatId"] as? String ?? ""
                p.ytPrivacy = (b["status"] as? [String: Any])?["privacyStatus"] as? String ?? "public"
                p.ytLatency = (b["contentDetails"] as? [String: Any])?["latencyPreference"] as? String ?? "normal"
                p.ytLive = ((b["status"] as? [String: Any])?["lifeCycleStatus"] as? String) == "live"
                if let v = ((try await api().call("GET", "/videos", query: [.init(name: "part", value: "liveStreamingDetails"), .init(name: "id", value: p.ytVideoID)]))["items"] as? [[String: Any]])?.first {
                    p.ytViewers = Int((v["liveStreamingDetails"] as? [String: Any])?["concurrentViewers"] as? String ?? "") ?? 0
                }
            }
            if let s = ((try await api().call("GET", "/liveStreams", query: [.init(name: "part", value: "cdn"), .init(name: "mine", value: "true")]))["items"] as? [[String: Any]])?.first,
               let ing = ((s["cdn"] as? [String: Any])?["ingestionInfo"] as? [String: Any]) {
                p.ytStreamKey = ing["streamName"] as? String ?? ""
                if let a = ing["rtmpsIngestionAddress"] as? String, !a.isEmpty { p.ytIngest = a }
            }
            p.status = "YouTube updated"
        } catch { p.status = error.localizedDescription }
    }

    /// `liveBroadcasts.update` REPLACES every field in each part you send — so every part below is rebuilt from
    /// the last full fetch (`ytBroadcast`) with only the intended field changed, never sent as a bare title.
    /// Otherwise this would silently wipe the description, scheduledStartTime, and contentDetails/status.
    func apply(title: String, description: String, privacy: String, latency: String) async {
        guard !p.ytVideoID.isEmpty, let sn = p.ytBroadcast["snippet"] as? [String: Any] else { p.status = "No YouTube broadcast found. Create one in YouTube Studio first."; return }
        var st = p.ytBroadcast["status"] as? [String: Any] ?? [:]
        st["privacyStatus"] = privacy
        var cd = p.ytBroadcast["contentDetails"] as? [String: Any] ?? [:]
        cd["latencyPreference"] = latency
        let body: [String: Any] = [
            "id": p.ytVideoID,
            "snippet": ["title": title, "description": description, "scheduledStartTime": sn["scheduledStartTime"] ?? ""],
            "status": st, "contentDetails": cd,
        ]
        await PlatformFlow.mutate(status: { self.p.status = $0 }, done: "YouTube updated", refresh: { await self.refresh() }) {
            _ = try await self.api().call("PUT", "/liveBroadcasts", query: [.init(name: "part", value: "snippet,status,contentDetails")], body: body)
        }
    }

    func send(_ text: String) async {
        guard !p.ytLiveChatID.isEmpty else { p.status = "No live chat on this broadcast yet"; return }
        await PlatformFlow.attempt(status: { self.p.status = $0 }) {
            _ = try await self.api().call("POST", "/liveChatMessages", query: [.init(name: "part", value: "snippet")],
                body: ["snippet": ["liveChatId": self.p.ytLiveChatID, "type": "textMessageEvent", "textMessageDetails": ["messageText": text]]])
        }
    }

    func disconnect() {
        p.store.forget("yt")
        p.ytUser = ""; p.ytTitle = ""; p.ytVideoID = ""; p.ytStreamKey = ""
        p.ytDescription = ""; p.ytPrivacy = "public"; p.ytLatency = "normal"
    }

    /// One page of `liveChat/messages` for the broadcast's live chat (same id `send` posts to).
    /// Needs no new scope - `youtube.force-ssl` already covers reading. nil when there's no live chat yet
    /// (broadcast not started/found), so the poller backs off instead of erroring.
    func pollLiveChat(pageToken: String?) async throws -> (items: [[String: Any]], nextPageToken: String?, pollingIntervalMillis: Int)? {
        guard !p.ytLiveChatID.isEmpty else { return nil }
        var query = [URLQueryItem(name: "liveChatId", value: p.ytLiveChatID), URLQueryItem(name: "part", value: "snippet,authorDetails")]
        if let pageToken { query.append(.init(name: "pageToken", value: pageToken)) }
        let json = try await api().call("GET", "/liveChat/messages", query: query)
        return (json["items"] as? [[String: Any]] ?? [], json["nextPageToken"] as? String, json["pollingIntervalMillis"] as? Int ?? 5000)
    }
}
