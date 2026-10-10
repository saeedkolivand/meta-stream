import XCTest
import CoreGraphics
import Foundation
@testable import MetaStream

@MainActor
final class PrivacyTests: XCTestCase {
    func testDemoVisionToPixelIsPureScale() {
        // Vision and CIImage both use bottom-left, y-up: scaling is a pure scale, no flip.
        let box = CGRect(x: 0.25, y: 0.0, width: 0.5, height: 0.5)
        let px = CGRect(x: box.minX * 1000, y: box.minY * 800, width: box.width * 1000, height: box.height * 800)
        XCTAssertEqual(px, CGRect(x: 250, y: 0, width: 500, height: 400), "pure scale, matches CIImage's own bottom-left origin")
        XCTAssertEqual(800 - px.minY - px.height, 400, "flipped y for bottom-half box lands in top half up there")
    }

    func testDemoPad() {
        let padded = Privacy.pad(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), by: 0.3)
        XCTAssertEqual(padded.width, 0.32, accuracy: 0.001, "30% margin on each side grows width by 60%")
        XCTAssertEqual(padded.minX, 0.34, accuracy: 0.001, "padding also shifts the origin outward")
        let clamped = Privacy.pad(CGRect(x: 0, y: 0, width: 0.1, height: 0.1), by: 0.3)
        XCTAssertEqual(clamped.minX, 0, "padding clamps to the frame, never goes negative")
        XCTAssertEqual(clamped.minY, 0, "padding clamps to the frame, never goes negative")
    }

    func testDemoIsExpired() {
        let t0 = Date()
        XCTAssertFalse(Privacy.isExpired(lastDetection: t0, now: t0.addingTimeInterval(0.5), maxAge: 5), "inside the carry window")
        XCTAssertTrue(Privacy.isExpired(lastDetection: t0, now: t0.addingTimeInterval(6), maxAge: 5), "past the carry window")
    }

    func testDemoTextDetectionDue() {
        XCTAssertTrue(Privacy.textDetectionDue(pass: 1, everyN: 2, hasCarriedBoxes: false), "first pass always runs text")
        XCTAssertFalse(Privacy.textDetectionDue(pass: 1, everyN: 2, hasCarriedBoxes: true), "off-cadence pass skips once boxes carried")
        XCTAssertTrue(Privacy.textDetectionDue(pass: 2, everyN: 2, hasCarriedBoxes: true), "every Nth pass re-runs")
    }
}
