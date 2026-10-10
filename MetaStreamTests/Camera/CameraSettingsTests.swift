import XCTest
import AVFoundation
import CoreGraphics
@testable import MetaStream

final class CameraSettingsTests: XCTestCase {
    func testDemoClamped() {
        XCTAssertEqual(CameraSettings.clamped(5, min: 1, max: 3), 3, "zoom ceilings")
        XCTAssertEqual(CameraSettings.clamped(0.2, min: 1, max: 3), 1, "zoom floors")
        XCTAssertEqual(CameraSettings.clamped(2, min: 1, max: 3), 2, "zoom passes through in range")
        XCTAssertEqual(CameraSettings.clamped(50, min: 100, max: 800), 100, "ISO floors")
        XCTAssertEqual(CameraSettings.clamped(2000, min: 100, max: 800), 800, "ISO ceilings")
        XCTAssertEqual(CameraSettings.clamped(-10, min: -2, max: 2), -2, "EV floors")
        XCTAssertEqual(CameraSettings.clamped(10, min: -2, max: 2), 2, "EV ceilings")
    }

    func testDemoClampedSeconds() {
        XCTAssertEqual(CameraSettings.clampedSeconds(33.3, minSeconds: 0.001, maxSeconds: 1), 0.0333, accuracy: 0.0001, "ms -> s")
        XCTAssertEqual(CameraSettings.clampedSeconds(9999, minSeconds: 0.001, maxSeconds: 0.5), 0.5, "shutter ceilings")
    }

    func testDemoClampedGains() {
        let gains = AVCaptureDevice.WhiteBalanceGains(redGain: 10, greenGain: 0.1, blueGain: 3)
        let clamped = CameraSettings.clampedGains(gains, max: 4)
        XCTAssertEqual(clamped.redGain, 4)
        XCTAssertEqual(clamped.greenGain, 1)
        XCTAssertEqual(clamped.blueGain, 3, "WB gains clamp to [1, maxGain]")
    }

    func testDemoDevicePoint() {
        let tl = CGPoint(x: 0, y: 0)
        XCTAssertEqual(CameraSettings.devicePoint(forViewPoint: tl, orientation: .portrait, mirrored: false), CGPoint(x: 0, y: 1), "portrait top-left")
        XCTAssertEqual(CameraSettings.devicePoint(forViewPoint: tl, orientation: .portraitUpsideDown, mirrored: false), CGPoint(x: 1, y: 0), "portraitUpsideDown top-left")
        XCTAssertEqual(CameraSettings.devicePoint(forViewPoint: tl, orientation: .landscapeRight, mirrored: false), CGPoint(x: 0, y: 0), "landscapeRight top-left")
        XCTAssertEqual(CameraSettings.devicePoint(forViewPoint: tl, orientation: .landscapeLeft, mirrored: false), CGPoint(x: 1, y: 1), "landscapeLeft top-left")
        XCTAssertEqual(CameraSettings.devicePoint(forViewPoint: tl, orientation: .portrait, mirrored: true), CGPoint(x: 1, y: 1), "mirrored flips x")
        let center = CGPoint(x: 0.5, y: 0.5)
        XCTAssertEqual(CameraSettings.devicePoint(forViewPoint: center, orientation: .portrait, mirrored: false), CGPoint(x: 0.5, y: 0.5), "center maps to center")
    }

    func testDemoLiveCameraControlOrder() {
        XCTAssertEqual(LiveCameraControl.order(from: "zoom,torch"), [.zoom, .torch], "valid order parses in place")
        XCTAssertEqual(LiveCameraControl.order(from: "zoom,bogus,torch"), [.zoom, .torch], "unknown tokens dropped")
        XCTAssertEqual(LiveCameraControl.order(from: ""), LiveCameraControl.defaultOrder, "empty falls back to default")
        XCTAssertEqual(LiveCameraControl.order(from: "nope,also-nope"), LiveCameraControl.defaultOrder, "all-unknown falls back to default")
    }

    func testDemoLiveCameraControlRoundTrip() {
        let customOrder: [LiveCameraControl] = [.torch, .zoom, .mirror]
        XCTAssertEqual(LiveCameraControl.order(from: customOrder.map(\.rawValue).joined(separator: ",")), customOrder, "customise round trip: subset + reorder survives")
        XCTAssertEqual(LiveCameraControl.order(from: ""), LiveCameraControl.defaultOrder, "customise round trip: all-off falls back to defaults")
    }

    func testDemoPinchZoomClamp() {
        XCTAssertEqual(CameraSettings.clamped(2.0 * 1.5, min: 1, max: 5), 3.0, "pinch: base*magnification within range")
        XCTAssertEqual(CameraSettings.clamped(2.0 * 10, min: 1, max: 5), 5.0, "pinch: magnification clamps to device max")
        XCTAssertEqual(CameraSettings.clamped(2.0 * 0.1, min: 1, max: 5), 1.0, "pinch: magnification clamps to device min")
    }

    func testDemoZoomMultiplier() {
        XCTAssertEqual(CameraSettings.zoomMultiplier(wideFOVDegrees: 75, otherFOVDegrees: 75), 1.0, "same FOV -> 1x")
        XCTAssertGreaterThan(CameraSettings.zoomMultiplier(wideFOVDegrees: 75, otherFOVDegrees: 35), CameraSettings.zoomMultiplier(wideFOVDegrees: 75, otherFOVDegrees: 50), "narrower FOV -> bigger multiplier")
        XCTAssertEqual(CameraSettings.multiplierLabel(2.98), "3", "rounds hardware noise to a clean whole number")
        XCTAssertEqual(CameraSettings.multiplierLabel(0.52), "0.5", "keeps a genuine half-step")
    }

    func testDemoLensSwitchoverMapsOneToOne() {
        XCTAssertEqual(CameraSettings.clamped(3.0, min: 0.5, max: 10.0), 3.0, "switch-over factor maps 1:1 to videoZoomFactor")
        XCTAssertEqual(CameraSettings.clamped(0.5, min: 0.5, max: 10.0), 0.5, "ultra-wide sits at the virtual device floor")
        XCTAssertEqual(CameraSettings.clamped(0.2, min: 0.5, max: 10.0), 0.5, "request below floor clamps to floor, not 1.0")
    }

    func testDemoMaxUsableZoomFactor() {
        XCTAssertEqual(min(100.0, CameraSettings.maxUsableZoomFactor), 15, "huge device max caps at 15")
        XCTAssertEqual(min(6.0, CameraSettings.maxUsableZoomFactor), 6, "lower device ceiling never raised")
        XCTAssertEqual(CameraSettings.clamped(20, min: 1, max: min(100.0, CameraSettings.maxUsableZoomFactor)), 15, "apply clamp lands at 15")
        XCTAssertEqual(CameraSettings.clamped(20, min: 1, max: min(6.0, CameraSettings.maxUsableZoomFactor)), 6, "lower device ceiling still wins")
    }
}
