import XCTest
import Foundation
@testable import MetaStream

@MainActor
final class ChatFeedTests: XCTestCase {
    func testDemoKickDoubleEncodedFrame() throws {
        let kickSample = #"{"event":"App\\Events\\ChatMessageEvent","channel":"chatrooms.123.v2","data":"{\"content\":\"gg [emote:12345:catJAM]\",\"sender\":{\"id\":1,\"username\":\"viewerOne\"}}"}"#
        let kickOuter = try JSONSerialization.jsonObject(with: Data(kickSample.utf8)) as! [String: Any]
        let kickEvent = ChatFeed.parse(event: kickOuter["event"] as! String, data: kickOuter["data"] as? String)
        XCTAssertEqual(kickEvent?.origin, "kick")
        XCTAssertEqual(kickEvent?.user, "viewerOne")
        XCTAssertEqual(kickEvent?.text, "gg [emote:12345:catJAM]")
        XCTAssertEqual(kickEvent?.kind, .message)
        XCTAssertEqual(kickEvent?.amountCents, 0)
        XCTAssertNil(ChatFeed.parse(event: "pusher:ping", data: nil))
    }

    func testDemoTwitchChatMessage() throws {
        let twitchFrame = #"""
        {"metadata":{"message_id":"x","message_type":"notification","message_timestamp":"2024-01-01T00:00:00Z","subscription_type":"channel.chat.message","subscription_version":"1"},"payload":{"subscription":{"id":"s1","type":"channel.chat.message","version":"1","condition":{"broadcaster_user_id":"123","user_id":"123"}},"event":{"broadcaster_user_id":"123","broadcaster_user_login":"streamer","broadcaster_user_name":"Streamer","chatter_user_id":"456","chatter_user_login":"viewer","chatter_user_name":"Viewer","message_id":"m1","message":{"text":"gg well played","fragments":[]}}}}
        """#
        let twitchObj = try JSONSerialization.jsonObject(with: Data(twitchFrame.utf8)) as! [String: Any]
        let twitchMetadata = twitchObj["metadata"] as! [String: Any]
        let twitchPayload = twitchObj["payload"] as! [String: Any]
        let twitchEvent = ChatFeed.parseTwitchEvent(type: twitchMetadata["subscription_type"] as! String, event: twitchPayload["event"] as! [String: Any])
        XCTAssertEqual(twitchEvent?.kind, .message)
        XCTAssertEqual(twitchEvent?.user, "Viewer")
        XCTAssertEqual(twitchEvent?.text, "gg well played")
        XCTAssertEqual(twitchEvent?.origin, "twitch")
        XCTAssertEqual(ChatFeed.twitchSessionID(from: #"{"metadata":{"message_type":"session_welcome"},"payload":{"session":{"id":"abc123"}}}"#), "abc123")
        XCTAssertNil(ChatFeed.parseTwitchEvent(type: "channel.unknown.thing", event: [:]))
    }

    func testDemoYouTubeSuperChat() {
        let ytItem: [String: Any] = [
            "snippet": ["type": "superChatEvent", "superChatDetails": ["amountMicros": "5000000", "currency": "USD", "userComment": "love the stream"]],
            "authorDetails": ["displayName": "GenerousViewer"],
        ]
        let ytEvent = ChatFeed.parseYouTubeItem(ytItem)
        XCTAssertEqual(ytEvent?.kind, .tip)
        XCTAssertEqual(ytEvent?.user, "GenerousViewer")
        XCTAssertEqual(ytEvent?.text, "love the stream")
        XCTAssertEqual(ytEvent?.amountCents, 500)
        XCTAssertEqual(ytEvent?.origin, "youtube")
        XCTAssertNil(ChatFeed.parseYouTubeItem(["snippet": ["type": "membershipEvent"], "authorDetails": ["displayName": "x"]]))
    }
}
