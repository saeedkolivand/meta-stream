import XCTest
import Foundation
@testable import MetaStream

@MainActor
final class AlertParsersTests: XCTestCase {
    private func kick(_ name: String, _ data: String) -> ChatEvent? {
        KickChatProvider.parse(event: "App\\Events\\\(name)", data: data)
    }

    private func json(_ s: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any]
    }

    func testKickSub() {
        let e = kick("SubscriptionEvent", #"{"username":"sam","months":3}"#)
        XCTAssertEqual(e?.kind, .subscribe)
        XCTAssertEqual(e?.user, "sam")
        XCTAssertEqual(e?.count, 0)
    }

    func testKickGiftArrayAndQuantity() {
        let a = kick("GiftedSubscriptionsEvent", #"{"gifter_username":"gus","gifted_usernames":["a","b","c"]}"#)
        XCTAssertEqual(a?.user, "gus")
        XCTAssertEqual(a?.count, 3)
        let q = kick("GiftedSubscriptionsEvent", #"{"username":"gus","quantity":5}"#)
        XCTAssertEqual(q?.count, 5)
        XCTAssertEqual(kick("GiftedSubscriptionsEvent", #"{"username":"gus"}"#)?.count, 1)
    }

    func testKickHost() {
        let e = kick("StreamHostEvent", #"{"host_username":"hoster","number_viewers":42}"#)
        XCTAssertEqual(e?.kind, .raid)
        XCTAssertEqual(e?.count, 42)
    }

    func testKickFollow() {
        XCTAssertEqual(kick("FollowersUpdated", #"{"username":"fan","followed":true}"#)?.kind, .follow)
        XCTAssertNil(kick("FollowersUpdated", #"{"username":"fan","followed":false}"#))
        XCTAssertNil(kick("FollowersUpdated", #"{"followed":true}"#))
    }

    func testKickKicks() {
        let e = kick("KicksGifted", #"{"sender":{"username":"big"},"gift":{"amount":500},"message":"gg"}"#)
        XCTAssertEqual(e?.kind, .tip)
        XCTAssertEqual(e?.user, "big")
        XCTAssertEqual(e?.amountCents, 500)
        XCTAssertEqual(e?.text, "gg")
    }

    func testKickModifiedRulesAreHonoured() throws {
        let data = Data(#"{"version":1,"channels":["x.{channelId}","y.{nope}"],"events":{"New\\Name":{"kind":"follow","user":["who"]},"Bad":{"kind":"zzz","user":["u"]}}}"#.utf8)
        let rules = try XCTUnwrap(KickRules.decode(data))
        XCTAssertEqual(rules.events.count, 1)   // malformed rule skipped
        XCTAssertEqual(KickRules.channels(rules, chatroomID: 1, channelID: 7), ["x.7"])
        XCTAssertEqual(KickRules.parse(rules, event: "New\\Name", data: #"{"who":"ann"}"#)?.kind, .follow)
        XCTAssertNil(KickRules.parse(rules, event: "App\\Events\\SubscriptionEvent", data: #"{"username":"sam"}"#))
        XCTAssertNil(KickRules.decode(Data(#"{"version":2}"#.utf8)))
    }

    func testTwitchGiftAndResub() throws {
        let named = TwitchEventSubProvider.parseEvent(type: "channel.subscription.gift", event: try json(#"{"user_name":"gus","total":5,"is_anonymous":false}"#))
        XCTAssertEqual(named?.user, "gus")
        XCTAssertEqual(named?.count, 5)
        let anon = TwitchEventSubProvider.parseEvent(type: "channel.subscription.gift", event: try json(#"{"user_name":null,"total":2,"is_anonymous":true}"#))
        XCTAssertEqual(anon?.user, "Anonymous")
        XCTAssertEqual(anon?.count, 2)
        let resub = TwitchEventSubProvider.parseEvent(type: "channel.subscription.message", event: try json(#"{"user_name":"sam","message":{"text":"hi"}}"#))
        XCTAssertEqual(resub?.kind, .subscribe)
        XCTAssertEqual(resub?.count, 0)
        XCTAssertEqual(resub?.text, "hi")
    }

    func testYouTubeMemberAndGifting() {
        let author: [String: Any] = ["displayName": "Chan"]
        let sponsor = YouTubePollProvider.parseItem(["snippet": ["type": "newSponsorEvent"], "authorDetails": author])
        XCTAssertEqual(sponsor?.kind, .subscribe)
        XCTAssertEqual(sponsor?.count, 0)
        let gift = YouTubePollProvider.parseItem(["snippet": ["type": "membershipGiftingEvent", "membershipGiftingDetails": ["giftMembershipsCount": "4"]],
                                                  "authorDetails": author])
        XCTAssertEqual(gift?.count, 4)
        XCTAssertNil(YouTubePollProvider.parseItem(["snippet": ["type": "giftMembershipReceivedEvent"], "authorDetails": author]))
    }

    func testSubscribeSummaries() {
        XCTAssertEqual(DisplayNames.eventSummary(ChatEvent(kind: .subscribe, user: "u")), "u subscribed")
        XCTAssertEqual(DisplayNames.eventSummary(ChatEvent(kind: .subscribe, user: "u", count: 1)), "u gifted a sub")
        XCTAssertEqual(DisplayNames.eventSummary(ChatEvent(kind: .subscribe, user: "u", count: 5)), "u gifted 5 subs")
    }
}
