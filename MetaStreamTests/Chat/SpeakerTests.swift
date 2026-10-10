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

    func testDemoDropOldestBounding() {
        var q: [Int] = []
        for i in 1...7 { q.append(i); if q.count > 5 { q.removeFirst() } } // mirrors pushBounded's drop-oldest
        XCTAssertEqual(q, [3, 4, 5, 6, 7], "drop-oldest: \(q)")
    }
}
