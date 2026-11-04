import Engine
import XCTest
import CoreGraphics
@testable import MetaStream

@MainActor
final class StreamerTests: XCTestCase {
    func testDemoSteppedBitrate() {
        XCTAssertEqual(BitrateController.steppedBitrate(current: 1000, up: false, ceilingKbps: 4000, floorKbps: 500), 800, "down 20%")
        XCTAssertEqual(BitrateController.steppedBitrate(current: 600, up: false, ceilingKbps: 4000, floorKbps: 500), 500, "floors at 500")
        XCTAssertEqual(BitrateController.steppedBitrate(current: 500, up: false, ceilingKbps: 4000, floorKbps: 500), 500, "floor holds")
        XCTAssertEqual(BitrateController.steppedBitrate(current: 500, up: true, ceilingKbps: 4000, floorKbps: 500), 550, "up 10%")
        XCTAssertEqual(BitrateController.steppedBitrate(current: 3900, up: true, ceilingKbps: 4000, floorKbps: 500), 4000, "ceilings, no overshoot")
        XCTAssertEqual(BitrateController.steppedBitrate(current: 4000, up: true, ceilingKbps: 4000, floorKbps: 500), 4000, "ceiling is a ceiling")
    }

    func testDemoCleanSecondsBeforeUp() {
        XCTAssertEqual(BitrateController.cleanSecondsBeforeUp(current: 1229, failedAt: 3000), 5, "far below the failure: climb fast")
        XCTAssertEqual(BitrateController.cleanSecondsBeforeUp(current: 2400, failedAt: 3000), 15, "near the failure: probe slowly")
        XCTAssertEqual(BitrateController.cleanSecondsBeforeUp(current: 3000, failedAt: 0), 15, "no failure yet: probe slowly")
    }

    func testDemoBitrateController() {
        let t0 = Date(timeIntervalSince1970: 0)
        var ctl = BitrateController(ceilingKbps: 4000)
        XCTAssertEqual(ctl.tick(now: t0, congested: true, throughputKbps: 0)?.kbps, 3200, "backlog: down 20%")
        XCTAssertNil(ctl.tick(now: t0.addingTimeInterval(1), congested: true, throughputKbps: 0), "3 s cooldown")
        XCTAssertEqual(ctl.thermal(now: t0.addingTimeInterval(4), serious: true, reason: "hot")?.kbps, 2560, "heat: one forced step")
        XCTAssertNil(ctl.thermal(now: t0.addingTimeInterval(8), serious: true, reason: "hot"), "edge-triggered")
        for sec in 9...30 { _ = ctl.tick(now: t0.addingTimeInterval(Double(sec)), congested: false, throughputKbps: 9999) }
        XCTAssertEqual(ctl.currentKbps, 2560, "thermal ceiling holds while hot")
        _ = ctl.thermal(now: t0.addingTimeInterval(31), serious: false, reason: "")
        for sec in 32...40 { _ = ctl.tick(now: t0.addingTimeInterval(Double(sec)), congested: false, throughputKbps: 9999) }
        XCTAssertGreaterThan(ctl.currentKbps, 2560, "climbs once cool")
    }

    func testDemoPipRect() {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }
        let p = Streamer.pipRect(canvas: CGSize(width: 1080, height: 1920), corner: "topRight", size: "m", shape: "rounded")
        XCTAssertTrue(near(p.origin.x, 1080 - 324 - 43.2) && near(p.origin.y, 43.2) && near(p.width, 324) && near(p.height, 576), "pip topRight portrait M rounded: \(p)")
        let c = Streamer.pipRect(canvas: CGSize(width: 1920, height: 1080), corner: "bottomLeft", size: "s", shape: "circle")
        XCTAssertTrue(near(c.width, 237.6) && near(c.height, 237.6) && near(c.origin.x, 43.2) && near(c.origin.y, 1080 - 237.6 - 43.2), "pip bottomLeft landscape S circle: \(c)")
    }

    func testDemoCanvasPoint() {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }
        // 400x400 view, 1080x1920 canvas: aspect-fit leaves 87.5pt bars left/right.
        let hit = Streamer.canvasPoint(forViewPoint: CGPoint(x: 200, y: 200), viewSize: CGSize(width: 400, height: 400), canvas: CGSize(width: 1080, height: 1920))
        XCTAssertNotNil(hit)
        XCTAssertTrue(near(hit!.x, 540) && near(hit!.y, 960), "canvasPoint centre: \(String(describing: hit))")
        XCTAssertNil(Streamer.canvasPoint(forViewPoint: CGPoint(x: 10, y: 200), viewSize: CGSize(width: 400, height: 400), canvas: CGSize(width: 1080, height: 1920)), "canvasPoint letterbox")
    }
}
