import AVFoundation
import Foundation

/// Manual phone-camera controls layered on AVFoundation's automatic defaults. Every mode defaults to
/// "let the system decide" -- manual ISO/shutter/white-balance/lens-position only take effect when their
/// owning toggle is on. Not threaded through goLive()'s `quality:` parameter like PhoneQuality, because
/// ContentView (not touched by this change) builds that call site and doesn't know these fields exist --
/// see loadFromDefaults() below. Re-read and re-applied on every camera attach (switchTo(glasses:) in
/// Streamer.swift), so a front/back switch always gets the current values, not a Go-Live-time snapshot.
/// Device discovery lives in CameraDiscovery.swift; device writes live in CameraSettings+Apply.swift.
struct CameraSettings: Sendable {
    // ponytail: no longer a device selector (see captureDevice(position:)'s doc -- the zoom-scale rewrite
    // that fixed the ~6x-on-telephoto bug). Kept only so the lens strip/Settings picker have something to
    // highlight and old stored values keep loading; apply() never reads it.
    var lens = "wide"                    // "wide" | "ultrawide" | "telephoto"
    var zoom: Double = 1.0               // videoZoomFactor on whatever captureDevice(position:) attaches

    var focusMode = "continuous"         // "continuous" | "auto" | "manual"
    var lensPosition: Double = 0.5       // 0...1, used only when focusMode == "manual"
    var smoothAutoFocus = true           // designed for video; hunting is very visible while walking
    var faceDrivenAutoFocus = true

    var exposureManual = false
    var exposureBiasEV: Double = 0       // applied under auto exposure; custom mode ignores it (metering only)
    var manualISO: Double = 200
    var manualShutterMs: Double = 33.3   // ~1/30s
    var lowLightBoost = true

    var whiteBalanceManual = false
    var whiteBalanceTemperature: Double = 5500   // Kelvin
    var whiteBalanceTint: Double = 0

    var hdr = "auto"                     // "auto" | "on" | "off"
    var torchLevel: Double = 0           // 0 = off, else 0<level<=1
    var mirrored = false
    var geometricDistortionCorrection = true
}

extension CameraSettings {
    /// AppStorage backs UserDefaults.standard under the same keys SettingsView's Camera screen uses; read
    /// them directly here instead of widening goLive()'s parameter list (see the type doc above). Absent
    /// keys -- Settings never opened -- keep the struct's own defaults rather than reading UserDefaults'
    /// zero-value (0.0/false), which would silently mean "0x zoom" / "torch off forever" instead of
    /// "user hasn't chosen yet".
    static func loadFromDefaults() -> CameraSettings {
        let d = UserDefaults.standard
        var s = CameraSettings()
        if let v = d.object(forKey: "camLens") as? String { s.lens = v }
        if let v = d.object(forKey: "camZoom") as? Double { s.zoom = v }
        if let v = d.object(forKey: "camFocusMode") as? String { s.focusMode = v }
        if let v = d.object(forKey: "camLensPosition") as? Double { s.lensPosition = v }
        if let v = d.object(forKey: "camSmoothAutoFocus") as? Bool { s.smoothAutoFocus = v }
        if let v = d.object(forKey: "camFaceDrivenAutoFocus") as? Bool { s.faceDrivenAutoFocus = v }
        if let v = d.object(forKey: "camExposureManual") as? Bool { s.exposureManual = v }
        if let v = d.object(forKey: "camExposureBiasEV") as? Double { s.exposureBiasEV = v }
        if let v = d.object(forKey: "camManualISO") as? Double { s.manualISO = v }
        if let v = d.object(forKey: "camManualShutterMs") as? Double { s.manualShutterMs = v }
        if let v = d.object(forKey: "camLowLightBoost") as? Bool { s.lowLightBoost = v }
        if let v = d.object(forKey: "camWhiteBalanceManual") as? Bool { s.whiteBalanceManual = v }
        if let v = d.object(forKey: "camWBTemperature") as? Double { s.whiteBalanceTemperature = v }
        if let v = d.object(forKey: "camWBTint") as? Double { s.whiteBalanceTint = v }
        if let v = d.object(forKey: "camHDR") as? String { s.hdr = v }
        if let v = d.object(forKey: "camTorchLevel") as? Double { s.torchLevel = v }
        if let v = d.object(forKey: "camMirrored") as? Bool { s.mirrored = v }
        if let v = d.object(forKey: "camGDC") as? Bool { s.geometricDistortionCorrection = v }
        return s
    }
}

extension CameraSettings {
    // MARK: pure clamps -- see Self.demo(). One generic clamp for zoom/ISO/bias/lens-position/torch (all
    // "keep a requested Double in range"); ms->s is the one conversion, kept separate. apply(_:to:) below
    // calls these exact functions, so the self-check exercises production logic, not a parallel copy.
    static func clamped(_ requested: Double, min lo: Double, max hi: Double) -> Double {
        Swift.min(Swift.max(requested, lo), hi)
    }
    static func clampedSeconds(_ requestedMs: Double, minSeconds lo: Double, maxSeconds hi: Double) -> Double {
        clamped(requestedMs / 1000, min: lo, max: hi)
    }
    static func clampedGains(_ g: AVCaptureDevice.WhiteBalanceGains, max hi: Float) -> AVCaptureDevice.WhiteBalanceGains {
        func c(_ v: Float) -> Float { Swift.min(Swift.max(v, 1.0), hi) }
        return .init(redGain: c(g.redGain), greenGain: c(g.greenGain), blueGain: c(g.blueGain))
    }

    /// Maps a tap point normalized to the PREVIEW VIEW's own bounds (0...1, origin top-left) into
    /// AVCaptureDevice.focusPointOfInterest / exposurePointOfInterest space. Apple defines that space as
    /// FIXED to the sensor's natural landscape orientation regardless of the video orientation the capture
    /// connection is rotating to. AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)
    /// does this conversion for free, but this app's live preview is an AVSampleBufferDisplayLayer (shared
    /// with the glasses' raw HEVC feed), not an AVCaptureVideoPreviewLayer, so that convenience API isn't
    /// reachable here -- these are the same four 90-degree-rotation cases it computes internally.
    /// mirrored flips the x axis afterward, for the front camera when Settings' "Mirror" output toggle is on.
    static func devicePoint(forViewPoint p: CGPoint, orientation: AVCaptureVideoOrientation, mirrored: Bool) -> CGPoint {
        var x: CGFloat, y: CGFloat
        switch orientation {
        case .portrait:           x = p.y;     y = 1 - p.x
        case .portraitUpsideDown: x = 1 - p.y; y = p.x
        case .landscapeRight:     x = p.x;     y = p.y
        case .landscapeLeft:      x = 1 - p.x; y = 1 - p.y
        @unknown default:         x = p.x;     y = p.y
        }
        if mirrored { x = 1 - x }
        return CGPoint(x: Swift.min(Swift.max(x, 0), 1), y: Swift.min(Swift.max(y, 0), 1))
    }

    /// maxAvailableVideoZoomFactor on modern hardware runs far past anything usable -- pure digital
    /// upscaling that looks like mush. Apple's Camera app stops well short of it (15x on this device),
    /// and that practical ceiling is NOT exposed through any API. So, like SettingsView's bitrate ceilings
    /// and codec table, this is fixed, documented knowledge: one named constant instead of a magic 15.
    /// An ADDITIONAL ceiling on top of the device's own bounds, never a replacement.
    static let maxUsableZoomFactor: Double = 15
}

/// One entry in the live control strip ContentView opens over the preview. Tap-to-focus/expose is
/// deliberately not a case here -- it's a gesture directly on the preview, not a strip button.
/// Membership and order are user-configurable; ContentView renders `LiveCameraControl.order(from:)`'s
/// result rather than a hardcoded HStack, so adding/removing/reordering entries needs no ContentView change.
enum LiveCameraControl: String, CaseIterable {
    // stabilization/mirror: deliberate re-attaches, not live connection tweaks.
    // AE/AF lock and the grid/level overlays are NOT cases here: lock is a long-press gesture on the
    // preview, and grid/level are Settings-only viewfinder toggles, never strip buttons.
    case lens, zoom, exposure, torch, whiteBalanceLock, stabilization, mirror

    static let storageKey = "liveCameraControlOrder"
    static let defaultOrder: [LiveCameraControl] = [.lens, .zoom, .exposure, .torch, .whiteBalanceLock, .stabilization, .mirror]
    static let defaultOrderRaw = defaultOrder.map(\.rawValue).joined(separator: ",")

    /// Pure parse: comma-joined rawValues -> ordered cases. Unknown tokens are dropped; an empty string
    /// or one that parses to nothing falls back to defaultOrder so there's never a stored value that
    /// leaves the strip with no way to bring controls back. See Self.demo() below.
    static func order(from raw: String) -> [LiveCameraControl] {
        let parsed = raw.split(separator: ",").compactMap { LiveCameraControl(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        return parsed.isEmpty ? defaultOrder : parsed
    }

    /// Row label for the Customise-strip screen -- the strip itself never shows this text, only icons.
    var label: String {
        switch self {
        case .lens: return "Lens"
        case .zoom: return "Zoom"
        case .exposure: return "Exposure"
        case .torch: return "Torch"
        case .whiteBalanceLock: return "White balance lock"
        case .stabilization: return "Stabilisation"
        case .mirror: return "Mirror"
        }
    }
}

#if DEBUG
extension CameraSettings {
    /// Self-check for the pure conversions -- no device, no capture session.
    static func demo() {
        assert(clamped(5, min: 1, max: 3) == 3, "zoom ceilings")
        assert(clamped(0.2, min: 1, max: 3) == 1, "zoom floors")
        assert(clamped(2, min: 1, max: 3) == 2, "zoom passes through in range")
        assert(clamped(50, min: 100, max: 800) == 100, "ISO floors")
        assert(clamped(2000, min: 100, max: 800) == 800, "ISO ceilings")
        assert(clamped(-10, min: -2, max: 2) == -2, "EV floors")
        assert(clamped(10, min: -2, max: 2) == 2, "EV ceilings")
        assert(abs(clampedSeconds(33.3, minSeconds: 0.001, maxSeconds: 1) - 0.0333) < 0.0001, "ms -> s")
        assert(clampedSeconds(9999, minSeconds: 0.001, maxSeconds: 0.5) == 0.5, "shutter ceilings")
        let gains = AVCaptureDevice.WhiteBalanceGains(redGain: 10, greenGain: 0.1, blueGain: 3)
        let gainsClamped = clampedGains(gains, max: 4)
        assert(gainsClamped.redGain == 4 && gainsClamped.greenGain == 1 && gainsClamped.blueGain == 3, "WB gains clamp to [1, maxGain]")

        // devicePoint: a tap at the view's top-left, each orientation, unmirrored.
        let tl = CGPoint(x: 0, y: 0)
        assert(devicePoint(forViewPoint: tl, orientation: .portrait, mirrored: false) == CGPoint(x: 0, y: 1), "portrait top-left")
        assert(devicePoint(forViewPoint: tl, orientation: .portraitUpsideDown, mirrored: false) == CGPoint(x: 1, y: 0), "portraitUpsideDown top-left")
        assert(devicePoint(forViewPoint: tl, orientation: .landscapeRight, mirrored: false) == CGPoint(x: 0, y: 0), "landscapeRight top-left")
        assert(devicePoint(forViewPoint: tl, orientation: .landscapeLeft, mirrored: false) == CGPoint(x: 1, y: 1), "landscapeLeft top-left")
        assert(devicePoint(forViewPoint: tl, orientation: .portrait, mirrored: true) == CGPoint(x: 1, y: 1), "mirrored flips x")
        let center = CGPoint(x: 0.5, y: 0.5)
        assert(devicePoint(forViewPoint: center, orientation: .portrait, mirrored: false) == CGPoint(x: 0.5, y: 0.5), "center maps to center in every orientation")

        // LiveCameraControl.order(from:): valid, unknown-token-dropping, and fallback cases.
        assert(LiveCameraControl.order(from: "zoom,torch") == [.zoom, .torch], "valid order parses in place")
        assert(LiveCameraControl.order(from: "zoom,bogus,torch") == [.zoom, .torch], "unknown tokens dropped")
        assert(LiveCameraControl.order(from: "") == LiveCameraControl.defaultOrder, "empty falls back to default")
        assert(LiveCameraControl.order(from: "nope,also-nope") == LiveCameraControl.defaultOrder, "all-unknown falls back to default")

        // Customise screen round trip: a subset + reorder survives storage; the all-off case falls back
        // to defaults rather than ever leaving the strip with nothing on it (see LiveControlsCustomizeView).
        let customOrder: [LiveCameraControl] = [.torch, .zoom, .mirror]
        assert(LiveCameraControl.order(from: customOrder.map(\.rawValue).joined(separator: ",")) == customOrder, "customise round trip: subset + reorder survives")
        assert(LiveCameraControl.order(from: "") == LiveCameraControl.defaultOrder, "customise round trip: all-off falls back to defaults, never an empty strip")

        // Pinch-to-zoom: base zoom (at gesture start) * MagnifyGesture.magnification, clamped.
        assert(clamped(2.0 * 1.5, min: 1, max: 5) == 3.0, "pinch: base*magnification within range")
        assert(clamped(2.0 * 10, min: 1, max: 5) == 5.0, "pinch: magnification clamps to device max")
        assert(clamped(2.0 * 0.1, min: 1, max: 5) == 1.0, "pinch: magnification clamps to device min")

        // Lens zoom multipliers: derived from field-of-view ratios, not a per-model guess.
        assert(zoomMultiplier(wideFOVDegrees: 75, otherFOVDegrees: 75) == 1.0, "same FOV -> 1x")
        assert(zoomMultiplier(wideFOVDegrees: 75, otherFOVDegrees: 35) > zoomMultiplier(wideFOVDegrees: 75, otherFOVDegrees: 50), "narrower FOV -> bigger multiplier")
        assert(multiplierLabel(2.98) == "3", "rounds hardware noise to a clean whole number")
        assert(multiplierLabel(0.52) == "0.5", "keeps a genuine half-step")

        // Zoom-scale fix: a lens's switch-over factor maps 1:1 to videoZoomFactor on the virtual device.
        assert(clamped(3.0, min: 0.5, max: 10.0) == 3.0, "a lens's switch-over factor maps 1:1 to videoZoomFactor on the virtual device")
        assert(clamped(0.5, min: 0.5, max: 10.0) == 0.5, "ultra-wide's switch-over sits at the virtual device's real (below-1.0) floor")
        assert(clamped(0.2, min: 0.5, max: 10.0) == 0.5, "a request below that floor still clamps to it, not to 1.0")

        // maxUsableZoomFactor (15): a deliberate ceiling on top of the device's own max, never a replacement.
        assert(min(100.0, maxUsableZoomFactor) == 15, "a device claiming a huge max (100) still caps at 15")
        assert(min(6.0, maxUsableZoomFactor) == 6, "a device whose real max (6) is already below 15 is never raised")
        assert(clamped(20, min: 1, max: min(100.0, maxUsableZoomFactor)) == 15, "apply()'s clamp: requesting past the cap lands at 15, not the device's own 100")
        assert(clamped(20, min: 1, max: min(6.0, maxUsableZoomFactor)) == 6, "apply()'s clamp: a lower device ceiling still wins")

        print("CameraSettings.demo() ok")
    }
}
#endif
