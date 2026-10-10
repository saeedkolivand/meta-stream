import Foundation

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
    private static let pusherAppKey = "32cbd69e4b950bf97679"
    private static let pusherURL = URL(string: "wss://ws-us2.pusher.com/app/\(pusherAppKey)?protocol=7&client=js&version=8.4.0-rc2&flash=false")!

    private let onEvent: @MainActor (ChatEvent) -> Void
    private var socket: URLSessionWebSocketTask?
    private var task: Task<Void, Never>?
    private var stopped = true
    private var slug = ""

    init(onEvent: @escaping @MainActor (ChatEvent) -> Void) { self.onEvent = onEvent }

    func start(slug: String) {
        stop()
        self.slug = slug
        stopped = false
        applog("chat", "starting kick chat for \(slug)")
        task = runWithBackoff(label: "kick chat", isStopped: { [weak self] in self?.stopped ?? true }) { [weak self] in
            guard let self else { return }
            let roomID = try await Self.chatroomID(slug: self.slug)
            try await self.connect(roomID: roomID)
        }
    }

    func start() { if !slug.isEmpty { start(slug: slug) } }
    func stop() {
        stopped = true
        task?.cancel(); task = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }

    private static func chatroomID(slug: String) async throws -> Int {
        var req = URLRequest(url: URL(string: "https://kick.com/api/v2/channels/\(slug)")!)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
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
        return id
    }

    private func connect(roomID: Int) async throws {
        let socket = URLSession.shared.webSocketTask(with: Self.pusherURL)
        self.socket = socket
        socket.resume()
        try await send(socket, ["event": "pusher:subscribe", "data": ["auth": "", "channel": "chatrooms.\(roomID).v2"]])
        applog("chat", "kick chat connected room=\(roomID)")
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
        guard let chatEvent = Self.parse(event: event, data: outer["data"] as? String) else { return }
        onEvent(chatEvent)
    }

    static func parse(event: String, data: String?) -> ChatEvent? {
        guard event == "App\\Events\\ChatMessageEvent", let data,
              let inner = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let content = inner["content"] as? String,
              let sender = inner["sender"] as? [String: Any],
              let username = sender["username"] as? String
        else { return nil }
        return ChatEvent(kind: .message, user: username, text: content, origin: "kick")
    }
}

// MARK: - Twitch (EventSub WebSocket)

@MainActor
final class TwitchEventSubProvider: ChatProvider {
    private static let eventSubURL = URL(string: "wss://eventsub.wss.twitch.tv/ws")!

    private let onEvent: @MainActor (ChatEvent) -> Void
    private weak var platforms: Platforms?
    private var socket: URLSessionWebSocketTask?
    private var task: Task<Void, Never>?
    private var stopped = true

    init(platforms: Platforms, onEvent: @escaping @MainActor (ChatEvent) -> Void) {
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
            return ChatEvent(kind: .message, user: user, text: text, origin: "twitch")
        case "channel.follow":
            guard let user = event["user_name"] as? String else { return nil }
            return ChatEvent(kind: .follow, user: user, origin: "twitch")
        case "channel.subscribe":
            guard let user = event["user_name"] as? String else { return nil }
            return ChatEvent(kind: .subscribe, user: user, origin: "twitch")
        case "channel.raid":
            guard let user = event["from_broadcaster_user_name"] as? String else { return nil }
            return ChatEvent(kind: .raid, user: user, count: event["viewers"] as? Int ?? 0, origin: "twitch")
        case "channel.cheer":
            let user = event["user_name"] as? String ?? "an anonymous cheerer"
            return ChatEvent(kind: .cheer, user: user, text: event["message"] as? String ?? "", count: event["bits"] as? Int ?? 0, origin: "twitch")
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
              let user = (item["authorDetails"] as? [String: Any])?["displayName"] as? String
        else { return nil }
        switch type {
        case "textMessageEvent":
            guard let text = (snippet["textMessageDetails"] as? [String: Any])?["messageText"] as? String else { return nil }
            return ChatEvent(kind: .message, user: user, text: text, origin: "youtube")
        case "superChatEvent", "superStickerEvent":
            let details = (snippet[type == "superChatEvent" ? "superChatDetails" : "superStickerDetails"] as? [String: Any]) ?? [:]
            let micros = (details["amountMicros"] as? String).flatMap(Int.init) ?? (details["amountMicros"] as? NSNumber)?.intValue ?? 0
            return ChatEvent(kind: .tip, user: user, text: details["userComment"] as? String ?? "", amountCents: micros / 10_000, origin: "youtube")
        default:
            return nil
        }
    }
}
