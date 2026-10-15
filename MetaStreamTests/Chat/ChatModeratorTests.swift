import XCTest
import Foundation
@testable import MetaStream

@MainActor
final class ChatModeratorTests: XCTestCase {
    func testLatinCheck() {
        XCTAssertTrue(ChatModeration.isMostlyLatin("gg well played"))
        XCTAssertTrue(ChatModeration.isMostlyLatin("très bien, merci"))
        XCTAssertFalse(ChatModeration.isMostlyLatin("سلام چطوری"))
        XCTAssertFalse(ChatModeration.isMostlyLatin("سلام دوست من hi"))
        XCTAssertFalse(ChatModeration.isMostlyLatin("12 !!"))
        XCTAssertFalse(ChatModeration.isMostlyLatin("ok"))   // too short to judge
    }

    func testHoldOverflow() {
        XCTAssertTrue(ChatModeration.shouldHold(waiting: 0))
        XCTAssertTrue(ChatModeration.shouldHold(waiting: ChatModeration.maxWaiting - 1))
        XCTAssertFalse(ChatModeration.shouldHold(waiting: ChatModeration.maxWaiting))
    }

    func testReviewTextEligibility() {
        XCTAssertEqual(ChatModeration.reviewText(for: ChatEvent(kind: .message, user: "a", text: "hello  there https://x.co")), "hello there")
        XCTAssertNil(ChatModeration.reviewText(for: ChatEvent(kind: .follow, user: "a", text: "hello there")))
        XCTAssertNil(ChatModeration.reviewText(for: ChatEvent(kind: .message, user: "a", text: "hello there", origin: "test")))
        XCTAssertNil(ChatModeration.reviewText(for: ChatEvent(kind: .message, user: "a", text: "سلام دوست")))
        XCTAssertNil(ChatModeration.reviewText(for: ChatEvent(kind: .message, user: "a", text: "kill yourself now")))   // word list already caught it
    }

    func testFlaggedIsOffensive() {
        var e = ChatEvent(kind: .message, user: "a", text: "hello there")
        XCTAssertFalse(e.offensive)
        e.flagged = true
        XCTAssertTrue(e.offensive)
    }

    func testTranscriptSkipsBlockedFlaggedAndNonLatin() {
        var flagged = ChatEvent(kind: .message, user: "c", text: "mean words here")
        flagged.flagged = true
        let t = ChatSummary.transcript([
            ChatEvent(kind: .message, user: "a", text: "nice stream"),
            ChatEvent(kind: .follow, user: "b"),
            flagged,
            ChatEvent(kind: .message, user: "d", text: "سلام دوست من"),
        ])
        XCTAssertEqual(t, "a: nice stream")
    }
}
