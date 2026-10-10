import Foundation

/// One chat or alert event, platform-agnostic. `origin` names the destination a viewer typed on
/// ("kick"/"twitch"/"youtube") and is only spoken when `Speaker.showOrigin` is set.
/// Two numeric fields cover everything: `amountCents` is money (tips), `count` is countable
/// things (raid viewers, cheered bits). ponytail: cents as Int, never Double — currency in
/// floating point is a rounding bug waiting to happen.
struct ChatEvent: Sendable {
    enum Kind: Equatable { case message, tip, cheer, follow, subscribe, raid }
    let kind: Kind
    let user: String
    var text: String = ""
    var amountCents: Int = 0
    var count: Int = 0
    var origin: String = ""
}

/// Live chat as one AsyncStream<ChatEvent> (text-to-speech drives off it) plus a recent-messages buffer
/// for a future chat UI. Kick, Twitch and YouTube each run independently and funnel into the same stream —
/// exactly one of these owns any given origin, so starting one never stops another. Restream chat can plug
/// into the same `events` stream later. Transports live in ChatProviders.swift; this type only multiplexes.
@MainActor
final class ChatFeed: ObservableObject {
    @Published private(set) var recent: [ChatEvent] = []   // last 100, across every origin

    let events: AsyncStream<ChatEvent>
    private let emit: AsyncStream<ChatEvent>.Continuation

    private var kick: KickChatProvider?
    private var twitch: TwitchEventSubProvider?
    private var youtube: YouTubePollProvider?

    init() {
        // ponytail: bufferingNewest caps memory if TTS ever falls behind a chat flood; unbounded isn't needed.
        (events, emit) = AsyncStream.makeStream(of: ChatEvent.self, bufferingPolicy: .bufferingNewest(200))
    }

    /// Stops every origin — Kick, Twitch and YouTube.
    func stop() { stopKick(); stopTwitch(); stopYouTube() }

    /// Connects to Kick chat for `slug` (the channel name from the stream URL) and stays connected until `stopKick()`.
    func start(kickSlug: String) {
        let provider = kick ?? KickChatProvider(onEvent: { [weak self] e in self?.yield(e) })
        kick = provider
        provider.start(slug: kickSlug)
    }

    func stopKick() { kick?.stop() }

    /// Connects to Twitch EventSub for the currently-authorized account and stays connected until
    /// `stopTwitch()`. Identity, subscription creation and scope bookkeeping live in `Platforms`.
    func startTwitch(platforms: Platforms) {
        stopTwitch()
        let provider = TwitchEventSubProvider(platforms: platforms, onEvent: { [weak self] e in self?.yield(e) })
        twitch = provider
        provider.start()
    }

    func stopTwitch() { twitch?.stop() }

    /// Polls YouTube live chat until `stopYouTube()`. No push option exists for liveChat - polling at the
    /// interval the API itself hands back (`pollingIntervalMillis`) is the contract, not a shortcut around one.
    func startYouTube(platforms: Platforms) {
        stopYouTube()
        let provider = YouTubePollProvider(platforms: platforms, onEvent: { [weak self] e in self?.yield(e) })
        youtube = provider
        provider.start()
    }

    func stopYouTube() { youtube?.stop() }

    // MARK: - shared sink

    func yield(_ e: ChatEvent) {
        recent.append(e)
        if recent.count > 100 { recent.removeFirst(recent.count - 100) }
        emit.yield(e)
    }
}

#if DEBUG
extension ChatFeed {
    /// Self-check: one realistic frame per transport, decoded into the ChatEvent Speaker expects. No framework.
    static func demo() {
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
