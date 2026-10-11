import XCTest
import Foundation
@testable import MetaStream

@MainActor
final class ChatBadgesTests: XCTestCase {
    private func json(_ s: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any]
    }

    func testTwitchEventSubBadgesAndColor() throws {
        let event = try json(#"""
        {"chatter_user_name":"ModGuy","message":{"text":"hi","fragments":[]},"color":"#1E90FF","badges":[{"set_id":"subscriber","id":"12","info":"14"},{"set_id":"moderator","id":"1","info":""},{"set_id":"bits","id":"100","info":""},{"set_id":"moderator","id":"1","info":""}]}
        """#)
        let e = TwitchEventSubProvider.parseEvent(type: "channel.chat.message", event: event)
        XCTAssertEqual(e?.badges, ["moderator", "subscriber"])   // dedupe, drop unknown "bits", display order
        XCTAssertEqual(e?.color, "#1E90FF")
    }

    func testTwitchNoColorOrBadges() throws {
        let event = try json(#"{"chatter_user_name":"Plain","message":{"text":"hi"},"color":"","badges":[]}"#)
        let e = TwitchEventSubProvider.parseEvent(type: "channel.chat.message", event: event)
        XCTAssertEqual(e?.badges, [])
        XCTAssertNil(e?.color)
    }

    func testKickIdentity() throws {
        let data = #"{"content":"hey","sender":{"id":1,"username":"kickMod","identity":{"color":"#e9113c","badges":[{"type":"broadcaster","text":"Broadcaster"},{"type":"og","text":"OG"},{"type":"sub_gifter","text":"Gifter","count":5}]}}}"#
        let e = KickChatProvider.parse(event: "App\Events\ChatMessageEvent", data: data)
        XCTAssertEqual(e?.badges, ["broadcaster", "og"])
        XCTAssertEqual(e?.color, "#E9113C")
    }

    func testKickWithoutIdentity() {
        let e = KickChatProvider.parse(event: "App\Events\ChatMessageEvent", data: #"{"content":"x","sender":{"id":1,"username":"u"}}"#)
        XCTAssertEqual(e?.badges, [])
        XCTAssertNil(e?.color)
    }

    func testYouTubeAuthorDetails() {
        let item: [String: Any] = [
            "snippet": ["type": "textMessageEvent", "textMessageDetails": ["messageText": "hello"]],
            "authorDetails": ["displayName": "Chan", "isChatOwner": false, "isChatModerator": true, "isChatSponsor": true, "isVerified": true],
        ]
        let e = YouTubePollProvider.parseItem(item)
        XCTAssertEqual(e?.badges, ["moderator", "verified", "subscriber"])
        XCTAssertNil(e?.color)
    }

    func testColorValidation() {
        XCTAssertEqual(ChatBadges.color("#abcdef"), "#ABCDEF")
        XCTAssertNil(ChatBadges.color("red"))
        XCTAssertNil(ChatBadges.color("#fff"))
        XCTAssertNil(ChatBadges.color("#GGGGGG"))
        XCTAssertNil(ChatBadges.color(nil))
    }

    func testReadableRGBBrightensDarkColors() throws {
        let dark = try XCTUnwrap(ChatBadges.readableRGB(hex: "#0000FF", minLuminance: 0.5))
        XCTAssertGreaterThanOrEqual(0.2126 * dark.r + 0.7152 * dark.g + 0.0722 * dark.b, 0.4999)
        let bright = try XCTUnwrap(ChatBadges.readableRGB(hex: "#FFFF00"))
        XCTAssertEqual(bright.r, 1, accuracy: 0.001)
        XCTAssertEqual(bright.g, 1, accuracy: 0.001)
        XCTAssertEqual(bright.b, 0, accuracy: 0.001)   // already bright: untouched
        XCTAssertNil(ChatBadges.readableRGB(hex: "nope"))
    }
}
