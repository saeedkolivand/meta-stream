import Foundation

/// Lenient Int from a JSON number or numeric string (platforms are inconsistent about which they send).
func chatInt(_ v: Any?) -> Int? { (v as? Int) ?? (v as? String).flatMap(Int.init) }

/// Shared reconnect ladder for chat providers: runs `work` until it returns/throws, then retries with
/// 1/2/4/8/15s backoff until stopped. Kick/Twitch pass one connection lifetime; YouTube passes its
/// never-returning poll loop (success sleeps live inside `work`, so this sleep only fires after failures).
@MainActor
func runWithBackoff(label: String, isStopped: @escaping @MainActor () -> Bool, work: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
    Task { @MainActor in
        var backoff = 1.0
        while !Task.isCancelled, !isStopped() {
            do {
                try await work()
                backoff = 1
            } catch {
                if !isStopped() { applog("chat", "\(label) error: \(error.localizedDescription)", error: true) }
            }
            guard !Task.isCancelled, !isStopped() else { return }
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 15)
        }
    }
}

@MainActor
protocol ChatProvider: AnyObject {
    func start()
    func stop()
}

// MARK: - Kick (anonymous public Pusher WebSocket, no OAuth)

@MainActor
final class KickChatProvider: ChatProvider {
    /// kick.com's API rejects non-browser agents; Emotes uses the same one for its channel lookup.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1"
    /// Last known Pusher app; Kick rotates it, so `pusherURL()` asks Kick for the live one first.
    private static let fallbackPusher = (key: "34bf7a0ff419a2a775b9", cluster: "us2")

    private let onEvent: @MainActor (ChatEvent) -> Void
    private let onClear: @MainActor () -> Void
    private let onRemove: @MainActor (_ messageID: String?, _ userID: String?, _ login: String?) -> Void
    private var socket: URLSessionWebSocketTask?
    private var task: Task<Void, Never>?
    private var stopped = true
    private var slug = ""
    /// Non-chat event names whose raw payload was already logged once (see `handle`).
    private var loggedEvents: Set<String> = []
    private var rules = KickRules.defaults

    init(onEvent: @escaping @MainActor (ChatEvent) -> Void, onClear: @escaping @MainActor () -> Void = {},
         onRemove: @escaping @MainActor (_ messageID: String?, _ userID: String?, _ login: String?) -> Void = { _, _, _ in }) {
        self.onEvent = onEvent
        self.onClear = onClear
        self.onRemove = onRemove
    }

    func start(slug: String) {
        stop()
        self.slug = slug
        stopped = false
        applog("chat", "starting kick chat for \(slug)")
        task = runWithBackoff(label: "kick chat", isStopped: { [weak self] in self?.stopped ?? true }) { [weak self] in
            guard let self else { return }
            let loaded = await KickRules.load()
            self.rules = loaded.rules
            applog("chat", "kick rules: \(loaded.source), \(loaded.rules.events.count) events, \(loaded.rules.channels.count) channels")
            let ids = try await Self.chatroomID(slug: self.slug)
            try await self.connect(roomID: ids.chatroom, channelID: ids.channel)
        }
    }

    func start() { if !slug.isEmpty { start(slug: slug) } }
    func stop() {
        stopped = true
        task?.cancel(); task = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }

    /// `chatroom` is the chat room id; `channel` is the channel's own top-level id (follower events live there).
    private static func chatroomID(slug: String) async throws -> (chatroom: Int, channel: Int?) {
        var req = URLRequest(url: URL(string: "https://kick.com/api/v2/channels/\(slug)")!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chatroom = json["chatroom"] as? [String: Any],
              let id = chatroom["id"] as? Int
        else {
            applog("chat", "kick channel lookup failed slug=\(slug) code=\(code) body=\(String(decoding: data.prefix(200), as: UTF8.self))", error: true)
            throw NSError(domain: "ChatFeed", code: 1, userInfo: [NSLocalizedDescriptionKey: "Kick channel lookup failed for \(slug) (HTTP \(code))"])
        }
        return (id, json["id"] as? Int)
    }

    /// Same anonymous call kick.com's own web client makes to learn which Pusher app/cluster is live.
    private static func pusherURL() async -> URL {
        var req = URLRequest(url: URL(string: "https://web.kick.com/api/v1/realtime/connection")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "client": ["id": UUID().uuidString.lowercased(), "type": "web"],
            "capabilities": ["accepted_providers": [["provider": "pusher"]]],
        ])
        var (key, cluster) = fallbackPusher
        var live = false
        if let data = try? await URLSession.shared.data(for: req).0,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let connections = (json["data"] as? [String: Any])?["connections"] as? [[String: Any]],
           let creds = connections.first(where: { $0["provider"] as? String == "pusher" })?["credentials"] as? [String: Any],
           let liveKey = creds["app_key"] as? String, let liveCluster = creds["cluster"] as? String {
            (key, cluster) = (liveKey, liveCluster)
            live = true
        } else {
            applog("chat", "kick realtime lookup failed, using fallback pusher key", error: true)
        }
        applog("chat", "kick pusher key \(key.prefix(6))… cluster \(cluster) (\(live ? "live" : "fallback"))")
        return URL(string: "wss://ws-\(cluster).pusher.com/app/\(key)?protocol=7&client=js&version=8.4.0-rc2&flash=false")!
    }

    private func connect(roomID: Int, channelID: Int?) async throws {
        let socket = URLSession.shared.webSocketTask(with: await Self.pusherURL())
        self.socket = socket
        socket.resume()
        for channel in KickRules.channels(rules, chatroomID: roomID, channelID: channelID) {
            try await send(socket, ["event": "pusher:subscribe", "data": ["auth": "", "channel": channel]])
        }
        while !Task.isCancelled, !stopped {
            guard case .string(let text) = try await socket.receive() else { continue }
            try await handle(frame: text, socket: socket)
        }
    }

    private func send(_ socket: URLSessionWebSocketTask, _ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func handle(frame text: String, socket: URLSessionWebSocketTask) async throws {
        guard let outer = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let event = outer["event"] as? String else {
            applog("chat", "kick frame not JSON: \(text.prefix(200))", error: true)
            return
        }
        if event == "pusher:ping" { try await socket.send(.string(#"{"event":"pusher:pong"}"#)); return }
        if event == "pusher_internal:subscription_succeeded" { applog("chat", "kick chat connected \(outer["channel"] ?? "")"); return }
        if event == "pusher:error" { applog("chat", "kick pusher error: \(outer["data"] ?? "")", error: true); return }
        let data = outer["data"] as? String
        let chatEvent = Self.parse(event: event, data: data, rules: rules)
        // Undocumented payloads: log the first of each non-chat event (handled or not) to learn the real shapes.
        if !event.hasPrefix("pusher"), event != Self.chatMessage, loggedEvents.insert(event).inserted {
            applog("chat", "kick event \(event) on \(outer["channel"] as? String ?? ""): \(String((data ?? "").prefix(300)))")
        }
        if event == Self.chatClear { onClear() }
        if event == Self.messageDeleted || event == Self.userBanned,
           let d = data.flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }) {
            if event == Self.messageDeleted, let id = (d["message"] as? [String: Any])?["id"] as? String { onRemove(id, nil, nil) }
            if event == Self.userBanned, let u = d["user"] as? [String: Any] {
                onRemove(nil, (u["id"] as? NSNumber)?.stringValue ?? u["id"] as? String, u["username"] as? String)
            }
        }
        if let chatEvent { onEvent(chatEvent) }
    }

    private static let chatMessage = "App\\Events\\ChatMessageEvent"
    private static let chatClear = "App\\Events\\ChatroomClearEvent"   // you or a mod cleared chat (on kick.com or via /clear)
    // Captured 2026-10-19: {"message":{"id":"<message id>"},"aiModerated":false,...} (a mod's delete, or AutoMod)
    private static let messageDeleted = "App\\Events\\MessageDeletedEvent"
    // A timeout ("duration": minutes) or ban ("permanent": true): {"user":{"id":98713098,"username":"...",...},...}
    private static let userBanned = "App\\Events\\UserBannedEvent"

    /// Chat messages are parsed here; every other event goes through the (remote-overridable) `rules` table.
    static func parse(event: String, data: String?, rules: KickRules.Rules = KickRules.defaults) -> ChatEvent? {
        guard event == chatMessage else { return KickRules.parse(rules, event: event, data: data) }
        guard let data, let inner = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else { return nil }
        return parseMessage(inner)
    }

    private static func parseMessage(_ inner: [String: Any]) -> ChatEvent? {
        guard let content = inner["content"] as? String,
              let sender = inner["sender"] as? [String: Any],
              let username = sender["username"] as? String
        else { return nil }
        let identity = sender["identity"] as? [String: Any]
        return ChatEvent(kind: .message, user: username, text: content, origin: "kick",
                         badges: ChatBadges.kick(identity), color: ChatBadges.color(identity?["color"]),
                         id: inner["id"] as? String ?? "", userId: chatInt(sender["id"]).map(String.init) ?? "")
    }
}

// MARK: - Twitch (EventSub WebSocket)

@MainActor
final class TwitchEventSubProvider: ChatProvider {
    private static let eventSubURL = URL(string: "wss://eventsub.wss.twitch.tv/ws")!

    private let onEvent: @MainActor (ChatEvent) -> Void
    private let onClear: @MainActor () -> Void
    private let onRemove: @MainActor (_ messageID: String?, _ userID: String?, _ login: String?) -> Void
    private weak var platforms: Platforms?
    private var socket: URLSessionWebSocketTask?
    private var task: Task<Void, Never>?
    private var stopped = true

    init(platforms: Platforms, onEvent: @escaping @MainActor (ChatEvent) -> Void, onClear: @escaping @MainActor () -> Void = {},
         onRemove: @escaping @MainActor (_ messageID: String?, _ userID: String?, _ login: String?) -> Void = { _, _, _ in }) {
        self.onClear = onClear
        self.onRemove = onRemove
        self.platforms = platforms
        self.onEvent = onEvent
    }

    func start() {
        guard let platforms else { return }
        stop()
        stopped = false
        applog("chat", "starting twitch eventsub")
        task = runWithBackoff(label: "twitch eventsub", isStopped: { [weak self] in self?.stopped ?? true }) { [weak self] in
            guard let self, let platforms = self.platforms else { return }
            try await self.connect(platforms: platforms)
        }
        _ = platforms
    }

    func stop() {
        stopped = true
        task?.cancel(); task = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }

    private func connect(platforms: Platforms) async throws {
        var url = Self.eventSubURL
        reconnect: while !Task.isCancelled, !stopped {
            let socket = URLSession.shared.webSocketTask(with: url)
            self.socket = socket
            socket.resume()
            guard case .string(let welcomeText) = try await socket.receive(),
                  let sessionID = Self.sessionID(from: welcomeText)
            else { throw NSError(domain: "ChatFeed", code: 2, userInfo: [NSLocalizedDescriptionKey: "Twitch EventSub: no session_welcome"]) }
            applog("chat", "twitch eventsub connected session=\(sessionID)")
            await platforms.twitchSubscribeEventSub(sessionID: sessionID)

            while !Task.isCancelled, !stopped {
                guard case .string(let text) = try await socket.receive() else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                      let metadata = obj["metadata"] as? [String: Any],
                      let messageType = metadata["message_type"] as? String,
                      let payload = obj["payload"] as? [String: Any]
                else {
                    applog("chat", "twitch frame not JSON: \(text.prefix(200))", error: true)
                    continue
                }
                switch messageType {
                case "session_keepalive":
                    break
                case "session_reconnect":
                    if let s = (payload["session"] as? [String: Any])?["reconnect_url"] as? String, let newURL = URL(string: s) {
                        url = newURL
                    }
                    socket.cancel(with: .goingAway, reason: nil)
                    continue reconnect
                case "notification":
                    if metadata["subscription_type"] as? String == "channel.chat.clear" { onClear(); continue }
                    if let e = payload["event"] as? [String: Any] {
                        switch metadata["subscription_type"] as? String {
                        case "channel.chat.message_delete": onRemove(e["message_id"] as? String, nil, nil); continue
                        case "channel.chat.clear_user_messages":   // a ban or timeout clears that user's messages
                            onRemove(nil, e["target_user_id"] as? String, e["target_user_login"] as? String); continue
                        default: break
                        }
                    }
                    guard let subType = metadata["subscription_type"] as? String,
                          let event = payload["event"] as? [String: Any],
                          let chatEvent = Self.parseEvent(type: subType, event: event)
                    else { continue }
                    onEvent(chatEvent)
                default:
                    break
                }
            }
            return
        }
    }

    static func sessionID(from welcomeText: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(welcomeText.utf8)) as? [String: Any],
              (obj["metadata"] as? [String: Any])?["message_type"] as? String == "session_welcome"
        else { return nil }
        return ((obj["payload"] as? [String: Any])?["session"] as? [String: Any])?["id"] as? String
    }

    static func parseEvent(type: String, event: [String: Any]) -> ChatEvent? {
        switch type {
        case "channel.chat.message":
            guard let user = event["chatter_user_name"] as? String,
                  let text = (event["message"] as? [String: Any])?["text"] as? String
            else { return nil }
            return ChatEvent(kind: .message, user: user, text: text, origin: "twitch",
                             badges: ChatBadges.twitch(event["badges"]), color: ChatBadges.color(event["color"]),
                             id: event["message_id"] as? String ?? "", userId: event["chatter_user_id"] as? String ?? "")
        case "channel.follow":
            guard let user = event["user_name"] as? String else { return nil }
            return ChatEvent(kind: .follow, user: user, origin: "twitch")
        case "channel.subscribe":
            // Recipients of a gift arrive here too (is_gift); channel.subscription.gift already counts them.
            guard let user = event["user_name"] as? String, event["is_gift"] as? Bool != true else { return nil }
            return ChatEvent(kind: .subscribe, user: user, origin: "twitch", tier: twitchTier(event))
        case "channel.raid":
            guard let user = event["from_broadcaster_user_name"] as? String else { return nil }
            return ChatEvent(kind: .raid, user: user, count: event["viewers"] as? Int ?? 0, origin: "twitch")
        case "channel.cheer":
            let user = event["user_name"] as? String ?? "an anonymous cheerer"
            return ChatEvent(kind: .cheer, user: user, text: event["message"] as? String ?? "", count: event["bits"] as? Int ?? 0, origin: "twitch")
        default:
            return parseSubscriptionEvent(type: type, event: event)
        }
    }

    /// EventSub's "1000" / "2000" / "3000" (Prime arrives as "1000").
    private static func twitchTier(_ event: [String: Any]) -> Int {
        ((event["tier"] as? String).flatMap(Int.init) ?? 1000) / 1000
    }

    /// Gifted subs (`total` of them; an anonymous gifter has a null user_name) and resubs with a message.
    private static func parseSubscriptionEvent(type: String, event: [String: Any]) -> ChatEvent? {
        switch type {
        case "channel.subscription.gift":
            let user = event["user_name"] as? String ?? "Anonymous"
            return ChatEvent(kind: .subscribe, user: user, count: max(chatInt(event["total"]) ?? 1, 1), origin: "twitch", tier: twitchTier(event))
        case "channel.subscription.message":
            guard let user = event["user_name"] as? String else { return nil }
            return ChatEvent(kind: .subscribe, user: user, text: (event["message"] as? [String: Any])?["text"] as? String ?? "", origin: "twitch",
                             tier: twitchTier(event))
        default:
            return nil
        }
    }
}

// MARK: - YouTube (liveChat/messages polling)

@MainActor
final class YouTubePollProvider: ChatProvider {
    private let onEvent: @MainActor (ChatEvent) -> Void
    private weak var platforms: Platforms?
    private var task: Task<Void, Never>?
    private var stopped = true
    private var pageToken: String?

    init(platforms: Platforms, onEvent: @escaping @MainActor (ChatEvent) -> Void) {
        self.platforms = platforms
        self.onEvent = onEvent
    }

    func start() {
        guard let platforms else { return }
        stop()
        stopped = false
        pageToken = nil
        applog("chat", "starting youtube chat poll")
        task = runWithBackoff(label: "youtube chat poll", isStopped: { [weak self] in self?.stopped ?? true }) { [weak self] in
            guard let self, let platforms = self.platforms else { return }
            while !Task.isCancelled, !self.stopped {
                guard let page = try await platforms.ytPollLiveChat(pageToken: self.pageToken) else {
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
                self.pageToken = page.nextPageToken
                for item in page.items {
                    guard let e = Self.parseItem(item) else { continue }
                    self.onEvent(e)
                }
                try? await Task.sleep(for: .milliseconds(max(page.pollingIntervalMillis, 2000)))
            }
        }
        _ = platforms
    }

    func stop() {
        stopped = true
        task?.cancel(); task = nil
    }

    static func parseItem(_ item: [String: Any]) -> ChatEvent? {
        guard let snippet = item["snippet"] as? [String: Any],
              let type = snippet["type"] as? String,
              let author = item["authorDetails"] as? [String: Any],
              let user = author["displayName"] as? String
        else { return nil }
        switch type {
        case "textMessageEvent":
            guard let text = (snippet["textMessageDetails"] as? [String: Any])?["messageText"] as? String else { return nil }
            return ChatEvent(kind: .message, user: user, text: text, origin: "youtube", badges: ChatBadges.youtube(author))
        case "superChatEvent", "superStickerEvent":
            let details = (snippet[type == "superChatEvent" ? "superChatDetails" : "superStickerDetails"] as? [String: Any]) ?? [:]
            let micros = (details["amountMicros"] as? String).flatMap(Int.init) ?? (details["amountMicros"] as? NSNumber)?.intValue ?? 0
            let currency = details["currency"] as? String ?? "USD"
            return ChatEvent(kind: .tip, user: user, text: details["userComment"] as? String ?? "", amountCents: micros / 10_000,
                             money: Money(Decimal(micros) / 1_000_000, currency), origin: "youtube")
        default:
            return parseMembership(type: type, snippet: snippet, user: user)
        }
    }

    /// New members, milestones and gifted memberships map to `subscribe`; per-recipient giftMembershipReceivedEvent is ignored (spam).
    private static func parseMembership(type: String, snippet: [String: Any], user: String) -> ChatEvent? {
        switch type {
        case "newSponsorEvent":
            return ChatEvent(kind: .subscribe, user: user, origin: "youtube")
        case "memberMilestoneChatEvent":
            let comment = (snippet["memberMilestoneChatDetails"] as? [String: Any])?["userComment"] as? String ?? ""
            return ChatEvent(kind: .subscribe, user: user, text: comment, origin: "youtube")
        case "membershipGiftingEvent":
            let n = chatInt((snippet["membershipGiftingDetails"] as? [String: Any])?["giftMembershipsCount"]) ?? 1
            return ChatEvent(kind: .subscribe, user: user, count: max(n, 1), origin: "youtube")
        default:
            return nil
        }
    }
}
