import XCTest
import Foundation
@testable import MetaStream

@MainActor
final class PlatformsTests: XCTestCase {
    func testDemoMissingScopeFeatures() {
        let granted: Set<String> = ["channel:manage:broadcast", "user:read:chat", "clips:edit", "channel:read:ads", "channel:manage:ads"]
        let missing = Platforms.missingScopeFeatures(granted: granted)
        let want = ["announcements", "chat lockdown", "cheers", "commercial", "follows", "moderation", "raids", "subscriptions"]
        XCTAssertEqual(missing, want, "twitch scope-gap mismatch: got \(missing), want \(want)")
    }

    func testDemoMissingScopeFeaturesEmptyGrant() {
        XCTAssertEqual(Platforms.missingScopeFeatures(granted: []).count, Platforms.twitchChatScopes.count + Platforms.twitchActionScopes.count, "empty grant should miss every feature")
    }
}
