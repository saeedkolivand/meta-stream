import XCTest
import Foundation
@testable import MetaStream

@MainActor
final class EmotesTests: XCTestCase {
    func testDemoTokenizeMixedMessage() {
        let byName = ["PogChamp": URL(string: "https://cdn.example.com/pog.webp")!]
        let runs = Emotes.tokenize("gg PogChamp [emote:12345:catJAM] well played", byName: byName)
        XCTAssertEqual(runs.count, 4)
        XCTAssertEqual(runs[0], .text("gg"))
        XCTAssertEqual(runs[1], .emote(byName["PogChamp"]!))
        XCTAssertEqual(runs[2], .emote(URL(string: "https://files.kick.com/emotes/12345/fullsize")!))
        XCTAssertEqual(runs[3], .text("well played"))
    }

    func testDemoTokenizePlainAndKickOnly() {
        XCTAssertEqual(Emotes.tokenize("no emotes here", byName: [:]), [.text("no emotes here")])
        XCTAssertEqual(Emotes.tokenize("[emote:1:x]", byName: [:]), [.emote(URL(string: "https://files.kick.com/emotes/1/fullsize")!)])
    }
}
