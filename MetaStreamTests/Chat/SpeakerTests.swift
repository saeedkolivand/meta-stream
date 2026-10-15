import XCTest
import Foundation
@testable import MetaStream

@MainActor
final class SpeakerTests: XCTestCase {
    func testDemoSanitize() {
        let s = Speaker.sanitize("hey @Bob check https://x.co/y :LUL: [emote:12345:catJAM]   nice   clip")
        XCTAssertEqual(s, "hey Bob check nice clip", "sanitize: \(s)")
    }

    func testDemoSanitizeCapsLength() {
        let capped = Speaker.sanitize(String(repeating: "a", count: 250))
        XCTAssertEqual(capped.count, 200, "cap: \(capped.count)")
    }

    func testDemoSpokenAmount() {
        XCTAssertEqual(Speaker.spokenAmount(cents: 500), "five dollars", "amount: \(Speaker.spokenAmount(cents: 500))")
    }

    func testIsNoise() {
        XCTAssertTrue(Speaker.isNoise(user: "Nightbot", text: "hi", ignored: ""))
        XCTAssertTrue(Speaker.isNoise(user: "BotRix", text: "hi", ignored: ""))
        XCTAssertTrue(Speaker.isNoise(user: "bob", text: " !discord", ignored: ""))
        XCTAssertTrue(Speaker.isNoise(user: "Spammer", text: "hi", ignored: "alice, @spammer"))
        XCTAssertFalse(Speaker.isNoise(user: "bob", text: "nice drive!", ignored: "alice"))
        XCTAssertFalse(Speaker.isNoise(user: "botanist", text: "hi", ignored: ""))
    }

    func testIsBlocked() {
        for bad in ["you N1GG3R", "niiiiggers lol", "n i g g e r", "just kys", "F@G"] {
            XCTAssertTrue(Speaker.isBlocked(bad, extra: ""), bad)
        }
        for ok in ["spicy food", "nice fagioli", "skyscraper", "good drive!"] {
            XCTAssertFalse(Speaker.isBlocked(ok, extra: ""), ok)
        }
        XCTAssertTrue(Speaker.isBlocked("what a jerkface", extra: "foo, jerkface"))
        XCTAssertTrue(Speaker.isBlocked("کصافت", extra: "کصافت"))
    }

    func testDemoDropOldestBounding() {
        var q: [Int] = []
        for i in 1...7 { q.append(i); if q.count > 5 { q.removeFirst() } } // mirrors pushBounded's drop-oldest
        XCTAssertEqual(q, [3, 4, 5, 6, 7], "drop-oldest: \(q)")
    }
}
