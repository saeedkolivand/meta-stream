import XCTest
@testable import MetaStream

final class LiveWidgetsTests: XCTestCase {
    func testWeatherEmoji() {
        let cases: [(Int, String)] = [(0, "☀️"), (2, "🌤️"), (3, "☁️"), (61, "🌧️"), (75, "❄️"), (81, "🌦️"), (95, "⛈️"), (1000, "🌡️")]
        for (code, emoji) in cases { XCTAssertEqual(WidgetWeather.emoji(code), emoji, "code \(code)") }
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
