import XCTest
@testable import MetaStream

final class LiveActivityPolicyTests: XCTestCase {
    private typealias State = StreamActivityAttributes.ContentState
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func state(phase: String = "live", kbps: Int = 2000, drops: Int = 0, muted: Bool = false) -> State {
        State(phase: phase, liveSince: t0, kbps: kbps, source: "phone", drops: drops, muted: muted)
    }

    func testFirstStateAlwaysPushes() {
        XCTAssertTrue(LiveActivityPolicy.shouldPush(old: nil, new: state(), lastPushAt: nil, now: t0))
    }

    func testKbpsOnlyChangeIsThrottled() {
        let old = state(kbps: 2000), new = state(kbps: 2400)
        XCTAssertFalse(LiveActivityPolicy.shouldPush(old: old, new: new, lastPushAt: t0, now: t0 + 14), "inside 15 s")
        XCTAssertTrue(LiveActivityPolicy.shouldPush(old: old, new: new, lastPushAt: t0, now: t0 + 15), "at 15 s")
    }

    func testUnchangedStateNeverPushes() {
        XCTAssertFalse(LiveActivityPolicy.shouldPush(old: state(), new: state(), lastPushAt: t0, now: t0 + 600))
    }

    func testPhaseDropsAndMuteChangesPushImmediately() {
        let old = state()
        for new in [state(phase: "reconnecting"), state(drops: 1), state(muted: true)] {
            XCTAssertTrue(LiveActivityPolicy.shouldPush(old: old, new: new, lastPushAt: t0, now: t0 + 1))
        }
    }
}
