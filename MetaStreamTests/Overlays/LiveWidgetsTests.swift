import XCTest
@testable import MetaStream

final class LiveWidgetsTests: XCTestCase {
    func testWeatherSymbol() {
        let cases: [(Int, String)] = [(0, "sun.max.fill"), (2, "cloud.sun.fill"), (3, "cloud.fill"), (61, "cloud.rain.fill"),
                                      (75, "snowflake"), (81, "cloud.sun.rain.fill"), (95, "cloud.bolt.rain.fill"),
                                      (1000, "thermometer.medium")]
        for (code, name) in cases { XCTAssertEqual(WidgetWeather.symbol(code), name, "code \(code)") }
    }

    func testRotatingLine() {
        let t = "a\nb\nc"
        func line(_ s: Double) -> String { OverlayCompositor.rotatingLine(t, seconds: 5, now: Date(timeIntervalSince1970: s)) }
        XCTAssertEqual(line(0), "a")
        XCTAssertEqual(line(5), "b")
        XCTAssertEqual(line(14.9), "c")
        XCTAssertEqual(line(15), "a")
    }

    func testRotatingLineSkipsBlankAndKeepsEmpty() {
        XCTAssertEqual(OverlayCompositor.rotatingLine("a\n \n\nb", seconds: 5, now: Date(timeIntervalSince1970: 5)), "b")
        XCTAssertEqual(OverlayCompositor.rotatingLine("", seconds: 5, now: Date(timeIntervalSince1970: 5)), "")
    }
}

final class SharedFixTests: XCTestCase {
    func testWireRoundTripAndRejectsJunk() {
        let f = SharedFix(lat: 35.7, lon: 51.4, speed: 12.5, accuracy: 5, time: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(SharedFix(wire: f.wire), f)
        for bad in ["", "?", "1,2,3,4", "91,0,0,5,1", "0,0,nan,5,1", "0,0,0,5,1,6", "0,0,999,5,1"] {
            XCTAssertNil(SharedFix(wire: bad), bad)
        }
    }
}

final class ChatBurstTests: XCTestCase {
    func testIsBurst() {
        let now = Date(timeIntervalSince1970: 100)
        func at(_ ago: Double) -> Date { now.addingTimeInterval(-ago) }
        XCTAssertFalse(ChatBurst.isBurst([], now: now))
        XCTAssertFalse(ChatBurst.isBurst([at(0.1), at(0.5)], now: now))
        XCTAssertTrue(ChatBurst.isBurst([at(0.1), at(0.5), at(0.9)], now: now))
        XCTAssertFalse(ChatBurst.isBurst([at(0.1), at(0.5), at(1.5)], now: now))
    }
}

final class AlertIslandTests: XCTestCase {
    func testPoseTimeline() {
        let start = AlertIsland.pose(at: 0, hold: 5, big: false)
        XCTAssertEqual(start.open, 0, accuracy: 0.001)
        XCTAssertEqual(start.progress, 0, accuracy: 0.001)
        XCTAssertEqual(start.lift, -1.5, accuracy: 0.001)
        let opened = AlertIsland.pose(at: 0.62, hold: 5, big: false)
        XCTAssertEqual(opened.open, 1, accuracy: 0.001)
        let settled = AlertIsland.pose(at: AlertIsland.enter, hold: 5, big: true)
        XCTAssertEqual(settled.progress, 1, accuracy: 0.001)
        XCTAssertEqual(settled.flash, 0, accuracy: 0.001)
        XCTAssertEqual(AlertIsland.pose(at: 0.62, hold: 5, big: true).flash, 0.9, accuracy: 0.001)
        let gone = AlertIsland.pose(at: AlertIsland.total(hold: 5), hold: 5, big: false)
        XCTAssertEqual(gone.open, 0, accuracy: 0.001)
        XCTAssertEqual(gone.alpha, 0, accuracy: 0.001)
    }

    func testAmountText() {
        XCTAssertEqual(AlertIsland.amountText(ChatEvent(kind: .tip, user: "a", amountCents: 2500), progress: 1), "$25")
        XCTAssertEqual(AlertIsland.amountText(ChatEvent(kind: .tip, user: "a", amountCents: 1250), progress: 1), "$12.50")
        XCTAssertEqual(AlertIsland.amountText(ChatEvent(kind: .raid, user: "a", count: 120), progress: 1), "120 viewers")
        XCTAssertEqual(AlertIsland.amountText(ChatEvent(kind: .cheer, user: "a", count: 300), progress: 0), "0 bits")
        XCTAssertNil(AlertIsland.amountText(ChatEvent(kind: .follow, user: "a"), progress: 1))
    }

    @MainActor func testBigTier() {
        XCTAssertTrue(AlertIsland.isBig(ChatEvent(kind: .tip, user: "a", amountCents: 1000)))
        XCTAssertFalse(AlertIsland.isBig(ChatEvent(kind: .tip, user: "a", amountCents: 999)))
        XCTAssertTrue(AlertIsland.isBig(ChatEvent(kind: .raid, user: "a", count: 50)))
    }
}
