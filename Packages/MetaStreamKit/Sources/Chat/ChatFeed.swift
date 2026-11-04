import CoreLogging
import CoreModel
import Foundation
import Observation
import Platforms

/// Live chat as one AsyncStream<ChatEvent> (text-to-speech drives off it) plus a recent-messages buffer
/// for a future chat UI. Kick, Twitch and YouTube each run independently and funnel into the same stream —
/// exactly one of these owns any given origin, so starting one never stops another. Restream chat can plug
/// into the same `events` stream later. Transports live in ChatProviders.swift; this type only multiplexes.
@MainActor @Observable
public final class ChatFeed {
    public private(set) var recent: [ChatEvent] = []   // last 100, across every origin
    /// Events yielded so far. Not observed: widgets poll it on their own tick instead of re-rendering SwiftUI.
    @ObservationIgnored public private(set) var serial = 0
    /// Bumped by every clear: a clear adds no event, so `serial` alone can't tell the on-screen chat to redraw.
    @ObservationIgnored public private(set) var clears = 0
    /// The chat sheet and the on-screen chat show only what arrived after the last clear: a clear empties them of
    /// everything (alerts and site events too, from any origin), while `recent` keeps events for the Event list.
    public private(set) var clearedAt = Date.distantPast
    public var visible: [ChatEvent] { recent.filter { $0.at > clearedAt } }
    public private(set) var lastFollower = ""
    public private(set) var lastSubscriber = ""
    public private(set) var flooding = false
    @ObservationIgnored private var floodTask: Task<Void, Never>?

    public let events: AsyncStream<ChatEvent>
    private let emit: AsyncStream<ChatEvent>.Continuation

    @ObservationIgnored private var kick: KickChatProvider?
    @ObservationIgnored private var twitch: TwitchEventSubProvider?
    @ObservationIgnored private var youtube: YouTubePollProvider?
    private let moderator = ChatModerator()

    public init() {
        // ponytail: bufferingNewest caps memory if TTS ever falls behind a chat flood; unbounded isn't needed.
        (events, emit) = AsyncStream.makeStream(of: ChatEvent.self, bufferingPolicy: .bufferingNewest(200))
    }

    /// Stops every origin — Kick, Twitch and YouTube.
    public func stop() { stopKick(); stopTwitch(); stopYouTube() }

    /// Connects to Kick chat for `slug` (the channel name from the stream URL) and stays connected until `stopKick()`.
    public func start(kickSlug: String) {
        let provider = kick ?? KickChatProvider(onEvent: { [weak self] e in self?.yield(e) },
                                                onClear: { [weak self] in self?.clear(origin: "kick") },
                                                onRemove: { [weak self] m, u, l in self?.remove(origin: "kick", messageID: m, userID: u, login: l) })
        kick = provider
        provider.start(slug: kickSlug)
    }

    public func stopKick() { kick?.stop() }

    /// Connects to Twitch EventSub for the currently-authorized account and stays connected until
    /// `stopTwitch()`. Identity, subscription creation and scope bookkeeping live in `Platforms`.
    public func startTwitch(platforms: Platforms) {
        stopTwitch()
        let provider = TwitchEventSubProvider(platforms: platforms, onEvent: { [weak self] e in self?.yield(e) },
                                              onClear: { [weak self] in self?.clear(origin: "twitch") },
                                              onRemove: { [weak self] m, u, l in self?.remove(origin: "twitch", messageID: m, userID: u, login: l) })
        twitch = provider
        provider.start()
    }

    public func stopTwitch() { twitch?.stop() }

    /// Polls YouTube live chat until `stopYouTube()`. No push option exists for liveChat - polling at the
    /// interval the API itself hands back (`pollingIntervalMillis`) is the contract, not a shortcut around one.
    public func startYouTube(platforms: Platforms) {
        stopYouTube()
        let provider = YouTubePollProvider(platforms: platforms, onEvent: { [weak self] e in self?.yield(e) })
        youtube = provider
        provider.start()
    }

    public func stopYouTube() { youtube?.stop() }

    /// Logs-screen load test: ChatFlood.perSecond fake messages per second for ChatFlood.seconds; call again to stop.
    public func toggleFlood() {
        if let t = floodTask { t.cancel(); floodTask = nil; flooding = false; return }
        flooding = true
        floodTask = Task { [weak self] in
            for i in 0..<(ChatFlood.perSecond * ChatFlood.seconds) {
                guard !Task.isCancelled, let self else { return }
                yield(ChatFlood.event(i))
                try? await Task.sleep(for: .milliseconds(1000 / ChatFlood.perSecond))
            }
            guard !Task.isCancelled, let self else { return }
            floodTask = nil
            flooding = false
        }
    }

    // MARK: - shared sink

    /// Every provider lands here; messages may wait up to 1.5 s for AI review before `publish`.
    public func yield(_ e: ChatEvent) {
        moderator.review(e) { [weak self] in self?.publish($0) }
    }

    private func publish(_ e: ChatEvent) {
        serial += 1
        if e.kind == .follow { lastFollower = e.user }
        if e.kind == .subscribe { lastSubscriber = e.user }
        recent.append(e)
        if recent.count > 100 { recent.removeFirst(recent.count - 100) }
        emit.yield(e)
    }

    /// A chat clear (our /clear, or one done on the platform by you or a mod): drops that origin's messages and moves
    /// `clearedAt`, so the chat sheet and the on-screen chat empty completely. The Event list still sees follows and
    /// subs. `serial` doesn't move, so nothing that reads `events(since:)` (alerts) sees old events again.
    public func clear(origin: String) {
        let before = recent.count
        recent.removeAll { $0.origin == origin && $0.kind == .message }
        clears += 1
        clearedAt = Date()
        applog("chat", "\(origin) chat cleared: \(before - recent.count) messages removed here")
    }

    /// A moderator deleted one message (`messageID`), or timed out / banned a user (their messages all go, like Twitch's
    /// own chat). Bumps `clears` so the on-screen chat redraws.
    public func remove(origin: String, messageID: String? = nil, userID: String? = nil, login: String? = nil) {
        let before = recent.count
        recent.removeAll { e in
            guard e.origin == origin, e.kind == .message else { return false }
            if let messageID { return e.id == messageID }
            if let userID, !userID.isEmpty, e.userId == userID { return true }
            if let login, !login.isEmpty, e.user.lowercased() == login.lowercased() { return true }
            return false
        }
        guard recent.count != before else { return }
        clears += 1
        applog("chat", "\(origin) moderation: \(before - recent.count) message(s) removed")
    }

    /// Events yielded after `serial` that are still in `recent` (older ones scrolled out of the 100-event buffer).
    public func events(since serial: Int) -> [ChatEvent] {
        guard serial < self.serial else { return [] }
        return Array(recent.suffix(min(self.serial - serial, recent.count)))
    }
}

#if DEBUG
extension ChatFeed {
    /// Self-check: one realistic frame per transport, decoded into the ChatEvent Speaker expects. No framework.
    public static func demo() {
        // Kick: Pusher double-JSON-encoding.
        let kickSample = #"{"event":"App\\Events\\ChatMessageEvent","channel":"chatrooms.123.v2","data":"{\"content\":\"gg [emote:12345:catJAM]\",\"sender\":{\"id\":1,\"username\":\"viewerOne\"}}"}"#
        let kickOuter = try! JSONSerialization.jsonObject(with: Data(kickSample.utf8)) as! [String: Any]
        let kickEvent = KickChatProvider.parse(event: kickOuter["event"] as! String, data: kickOuter["data"] as? String)
        assert(kickEvent?.origin == "kick")
        assert(kickEvent?.user == "viewerOne")
        assert(kickEvent?.text == "gg [emote:12345:catJAM]")
        assert(kickEvent?.kind == .message)
        assert(kickEvent?.amountCents == 0)
        assert(KickChatProvider.parse(event: "pusher:ping", data: nil) == nil)

        // Twitch: one EventSub channel.chat.message notification frame.
        let twitchFrame = #"""
        {"metadata":{"message_id":"x","message_type":"notification","message_timestamp":"2024-01-01T00:00:00Z","subscription_type":"channel.chat.message","subscription_version":"1"},"payload":{"subscription":{"id":"s1","type":"channel.chat.message","version":"1","condition":{"broadcaster_user_id":"123","user_id":"123"}},"event":{"broadcaster_user_id":"123","broadcaster_user_login":"streamer","broadcaster_user_name":"Streamer","chatter_user_id":"456","chatter_user_login":"viewer","chatter_user_name":"Viewer","message_id":"m1","message":{"text":"gg well played","fragments":[]}}}}
        """#
        let twitchObj = try! JSONSerialization.jsonObject(with: Data(twitchFrame.utf8)) as! [String: Any]
        let twitchMetadata = twitchObj["metadata"] as! [String: Any]
        let twitchPayload = twitchObj["payload"] as! [String: Any]
        let twitchEvent = TwitchEventSubProvider.parseEvent(type: twitchMetadata["subscription_type"] as! String, event: twitchPayload["event"] as! [String: Any])
        assert(twitchEvent?.kind == .message)
        assert(twitchEvent?.user == "Viewer")
        assert(twitchEvent?.text == "gg well played")
        assert(twitchEvent?.origin == "twitch")
        assert(TwitchEventSubProvider.sessionID(from: #"{"metadata":{"message_type":"session_welcome"},"payload":{"session":{"id":"abc123"}}}"#) == "abc123")
        assert(TwitchEventSubProvider.parseEvent(type: "channel.unknown.thing", event: [:]) == nil)

        // YouTube: one liveChatMessages.list superChatEvent item.
        let ytItem: [String: Any] = [
            "snippet": ["type": "superChatEvent", "superChatDetails": ["amountMicros": "5000000", "currency": "USD", "userComment": "love the stream"]],
            "authorDetails": ["displayName": "GenerousViewer"],
        ]
        let ytEvent = YouTubePollProvider.parseItem(ytItem)
        assert(ytEvent?.kind == .tip)
        assert(ytEvent?.user == "GenerousViewer")
        assert(ytEvent?.text == "love the stream")
        assert(ytEvent?.amountCents == 500)
        assert(ytEvent?.origin == "youtube")
        assert(YouTubePollProvider.parseItem(["snippet": ["type": "membershipEvent"], "authorDetails": ["displayName": "x"]]) == nil)

        applog("chat", "ChatFeed.demo() passed")
    }
}
#endif
