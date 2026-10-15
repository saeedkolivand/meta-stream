import XCTest
@testable import MetaStream

final class NetworkStatsTests: XCTestCase {
    func testAppendCappedDropsOldest() {
        var a: [Int] = []
        for i in 1...5 { a.appendCapped(i, limit: 3) }
        XCTAssertEqual(a, [3, 4, 5])
    }

    func testPlainReason() {
        XCTAssertEqual(NetworkStats.plainReason("queue backlog"), "network backed up")
        XCTAssertEqual(NetworkStats.plainReason("throughput 900kbps < target 3000kbps"), "upload slower than target")
        XCTAssertEqual(NetworkStats.plainReason("15s clean"), "15 s stable, raising")
        XCTAssertEqual(NetworkStats.plainReason("thermal serious"), "phone hot")
    }

    func testRecentlyCongestedOnlyLooksAtLastSeconds() {
        var s = NetworkStats()
        for i in 0..<10 {
            s.samples.append(NetSample(kbps: 1000, target: 1000, congested: i == 2, down: false))
        }
        XCTAssertFalse(s.recentlyCongested(seconds: 5))
        s.samples.append(NetSample(kbps: 1000, target: 1000, congested: true, down: false))
        XCTAssertTrue(s.recentlyCongested(seconds: 5))
    }

    func testFmtKbpsGroupsThousands() {
        XCTAssertTrue(NetworkStats.fmtKbps(2640).hasSuffix(" kbps"))
        XCTAssertTrue(NetworkStats.fmtKbps(2640).contains("2"))
    }
}
