import AVFoundation
import CoreMedia
import Foundation

/// CameraDiscovery: which physical/virtual devices exist at a position and what they can do.
/// Pure discovery — never writes to a device (see CameraSettings+Apply.swift for the writer).
/// Lens choice is not a device property -- it's a different physical AVCaptureDevice. Discovering one
/// per attach (rather than caching) is what makes "re-evaluated per camera" (front vs back capability)
/// actually happen: DiscoverySession runs fresh against whichever position is being attached right now.
enum CameraLens: String, CaseIterable {
    case wide, ultrawide, telephoto

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .wide: return .builtInWideAngleCamera
        case .ultrawide: return .builtInUltraWideCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }
    var label: String {
        switch self {
        case .wide: return "Wide (1x)"
        case .ultrawide: return "Ultra-wide"
        case .telephoto: return "Telephoto"
        }
    }
}

/// One button in the live lens-switch row: a physical lens paired with the exact zoom factor (and its
/// display label) THIS device's hardware actually puts it at -- see CameraSettings.lensOptions(position:).
struct LensOption: Equatable {
    let lens: CameraLens
    let zoomFactor: Double
    let label: String
}

extension CameraSettings {
    static func device(lens: String, position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let type = CameraLens(rawValue: lens)?.deviceType ?? .builtInWideAngleCamera
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: [type], mediaType: .video, position: position).devices.first
        if let found { return found }
        if type == .builtInWideAngleCamera { return nil }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    static func availableLenses(position: AVCaptureDevice.Position) -> [CameraLens] {
        CameraLens.allCases.filter {
            AVCaptureDevice.DiscoverySession(deviceTypes: [$0.deviceType], mediaType: .video, position: position).devices.first != nil
        }
    }

    private static func virtualDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position)
    }

    static func captureDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        virtualDevice(position: position) ?? device(lens: "wide", position: position)
    }

    static func lensOptions(position: AVCaptureDevice.Position) -> [LensOption] {
        let available = availableLenses(position: position)
        guard available.count > 1 else { return [] }

        var ultrawideFactor: Double?
        var telephotoFactor: Double?
        let virtual = virtualDevice(position: position)
        if let virtual {
            let switchOvers = virtual.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue)
            let virtualMin = Double(virtual.minAvailableVideoZoomFactor)
            if available.contains(.ultrawide), virtualMin < 1 {
                ultrawideFactor = virtualMin
            }
            if available.contains(.telephoto), let hi = switchOvers.max() {
                telephotoFactor = hi
            }
        }
        if available.contains(.ultrawide), ultrawideFactor == nil {
            ultrawideFactor = fieldOfViewMultiplier(of: .ultrawide, position: position)
        }
        if available.contains(.telephoto), telephotoFactor == nil {
            telephotoFactor = fieldOfViewMultiplier(of: .telephoto, position: position)
        }

        var options: [LensOption] = [LensOption(lens: .wide, zoomFactor: 1, label: "1")]
        if let m = ultrawideFactor { options.append(LensOption(lens: .ultrawide, zoomFactor: m, label: multiplierLabel(m))) }
        if let m = telephotoFactor { options.append(LensOption(lens: .telephoto, zoomFactor: m, label: multiplierLabel(m))) }
        return options.sorted { $0.zoomFactor < $1.zoomFactor }
    }

    private static func fieldOfViewMultiplier(of lens: CameraLens, position: AVCaptureDevice.Position) -> Double? {
        guard lens != .wide,
              let wide = device(lens: "wide", position: position), wide.activeFormat.videoFieldOfView > 0,
              let other = device(lens: lens.rawValue, position: position), other.activeFormat.videoFieldOfView > 0
        else { return nil }
        return zoomMultiplier(wideFOVDegrees: Double(wide.activeFormat.videoFieldOfView), otherFOVDegrees: Double(other.activeFormat.videoFieldOfView))
    }

    static func zoomMultiplier(wideFOVDegrees: Double, otherFOVDegrees: Double) -> Double {
        let halfWide = wideFOVDegrees / 2 * .pi / 180, halfOther = otherFOVDegrees / 2 * .pi / 180
        return tan(halfWide) / tan(halfOther)
    }

    static func multiplierLabel(_ m: Double) -> String {
        let rounded = (m * 2).rounded() / 2
        return rounded.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
    }
}

/// What SettingsView's Camera screen greys controls out against -- probed fresh whenever the fallback-
/// camera position picker changes, since front/back genuinely differ. One probe per POSITION, not per
/// lens: captureDevice(position:) attaches one (virtual, usually) device covering every lens, so that's
/// the only device whose capabilities matter. `nil` fields mean "camera unavailable".
struct CameraCapabilities {
    var zoomRange: ClosedRange<Double>
    var focusAuto: Bool
    var focusContinuous: Bool
    var focusManual: Bool
    var smoothAutoFocus: Bool
    var exposureManual: Bool
    var isoRange: ClosedRange<Double>
    var shutterRangeMs: ClosedRange<Double>
    var exposureBiasRange: ClosedRange<Double>
    var lowLightBoost: Bool
    var whiteBalanceManual: Bool
    var hdr: Bool
    var torch: Bool
    var geometricDistortionCorrection: Bool

    static func probe(position: AVCaptureDevice.Position) -> CameraCapabilities? {
        guard let device = CameraSettings.captureDevice(position: position) else { return nil }
        let f = device.activeFormat
        return CameraCapabilities(
            zoomRange: device.minAvailableVideoZoomFactor...max(device.minAvailableVideoZoomFactor, min(device.maxAvailableVideoZoomFactor, CameraSettings.maxUsableZoomFactor)),
            focusAuto: device.isFocusModeSupported(.autoFocus),
            focusContinuous: device.isFocusModeSupported(.continuousAutoFocus),
            focusManual: device.isLockingFocusWithCustomLensPositionSupported,
            smoothAutoFocus: device.isSmoothAutoFocusSupported,
            exposureManual: device.isExposureModeSupported(.custom),
            isoRange: Double(f.minISO)...Double(max(f.minISO, f.maxISO)),
            shutterRangeMs: (f.minExposureDuration.seconds * 1000)...max(f.minExposureDuration.seconds * 1000, f.maxExposureDuration.seconds * 1000),
            exposureBiasRange: Double(device.minExposureTargetBias)...Double(max(device.minExposureTargetBias, device.maxExposureTargetBias)),
            lowLightBoost: device.isLowLightBoostSupported,
            whiteBalanceManual: device.isWhiteBalanceModeSupported(.locked),
            hdr: f.isVideoHDRSupported,
            torch: device.hasTorch,
            geometricDistortionCorrection: device.isGeometricDistortionCorrectionSupported)
    }
}

/// What resolutions THIS position can actually shoot, and for each, the frame rates and stabilisation
/// modes that resolution's capture format(s) support. Built from AVCaptureSession.Preset support rather
/// than raw device.formats enumeration -- Streamer's capture pipeline already selects resolution via
/// mixer.setSessionPreset(phoneQuality.sessionPreset), so probing exactly those presets keeps this
/// incapable of ever offering a resolution the capture side can't actually set.
struct CameraFormatCapabilities {
    struct Resolution: Equatable {
        let height: Int
        let frameRates: [Int]
        let stabilizationModes: [String]

        func nearestFps(to desired: Int) -> Int {
            frameRates.min { abs($0 - desired) < abs($1 - desired) } ?? desired
        }
        func nearestStabilization(to desired: String) -> String {
            stabilizationModes.contains(desired) ? desired : "off"
        }
    }
    let resolutions: [Resolution]

    private static let candidates: [(height: Int, preset: AVCaptureSession.Preset, dims: (Int, Int))] =
        [(720, .hd1280x720, (1280, 720)), (1080, .hd1920x1080, (1920, 1080)), (2160, .hd4K3840x2160, (3840, 2160))]
    private static let standardFps = [15, 24, 25, 30, 50, 60, 120, 240]
    private static let stabilizationNames = ["standard", "cinematic", "action"]

    static func probe(position: AVCaptureDevice.Position) -> CameraFormatCapabilities? {
        guard let device = CameraSettings.captureDevice(position: position) else {
            applog("stream", "format probe: no capture device at position=\(position == .front ? "front" : "back")", error: true)
            return nil
        }
        let totalFormats = device.formats.count
        var perCandidate: [String] = []
        let resolutions: [Resolution] = candidates.compactMap { height, preset, dims in
            guard device.supportsSessionPreset(preset) else {
                perCandidate.append("\(height)p: preset unsupported")
                return nil
            }
            let matching = device.formats.filter {
                let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return (Int(d.width), Int(d.height)) == dims || (Int(d.height), Int(d.width)) == dims
            }
            guard !matching.isEmpty else {
                perCandidate.append("\(height)p: preset ok, 0/\(totalFormats) formats match dims \(dims)")
                return nil
            }
            var fps: Set<Int> = []
            for format in matching {
                for range in format.videoSupportedFrameRateRanges {
                    let lo = Int(range.minFrameRate.rounded(.up)), hi = Int(range.maxFrameRate.rounded(.down))
                    if lo <= hi { fps.formUnion(lo...hi) }
                }
            }
            let offeredFps = standardFps.filter { fps.contains($0) }
            guard !offeredFps.isEmpty else {
                perCandidate.append("\(height)p: \(matching.count) formats matched dims, but none of \(standardFps) is in their fps ranges (raw union: \(fps.sorted()))")
                return nil
            }
            let stab = stabilizationNames.filter { name in
                matching.contains { $0.isVideoStabilizationModeSupported(Streamer.stabilizationMode(name)) }
            }
            perCandidate.append("\(height)p: ok, \(matching.count) formats, fps=\(offeredFps), stab=\(["off"] + stab)")
            return Resolution(height: height, frameRates: offeredFps, stabilizationModes: ["off"] + stab)
        }
        applog("stream", "format probe: device=\(device.localizedName) type=\(device.deviceType.rawValue) "
            + "position=\(position == .front ? "front" : "back") formats=\(totalFormats) -- \(perCandidate.joined(separator: "; "))")
        guard !resolutions.isEmpty else {
            applog("stream", "format probe: 0/\(candidates.count) candidates survived -- Settings will show its no-format-info fallback, Resolution/Frame rate keep their last-saved values", error: true)
            return nil
        }
        return CameraFormatCapabilities(resolutions: resolutions.sorted { $0.height < $1.height })
    }

    func nearestResolution(to desiredHeight: Int) -> Resolution? {
        resolutions.min { abs($0.height - desiredHeight) < abs($1.height - desiredHeight) }
    }
}
