import XCTest
import CoreGraphics
@testable import MetaStream

@MainActor
final class StreamerTests: XCTestCase {
    func testDemoSteppedBitrate() {
        XCTAssertEqual(Streamer.steppedBitrate(current: 1000, up: false, ceilingKbps: 4000, floorKbps: 500), 800, "down 20%")
        XCTAssertEqual(Streamer.steppedBitrate(current: 600, up: false, ceilingKbps: 4000, floorKbps: 500), 500, "floors at 500")
        XCTAssertEqual(Streamer.steppedBitrate(current: 500, up: false, ceilingKbps: 4000, floorKbps: 500), 500, "floor is a floor")
        XCTAssertEqual(Streamer.steppedBitrate(current: 500, up: true, ceilingKbps: 4000, floorKbps: 500), 550, "up 10%")
        XCTAssertEqual(Streamer.steppedBitrate(current: 3900, up: true, ceilingKbps: 4000, floorKbps: 500), 4000, "ceilings, no overshoot")
        XCTAssertEqual(Streamer.steppedBitrate(current: 4000, up: true, ceilingKbps: 4000, floorKbps: 500), 4000, "ceiling is a ceiling")
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
