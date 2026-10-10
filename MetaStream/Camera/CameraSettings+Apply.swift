import AVFoundation
import CoreMedia

/// CameraApplier: writes a CameraSettings value to a live AVCaptureDevice. Each control group owns one
/// helper so focus/exposure/WB/image failures stay local to their group. Callers use `apply(_:to:log:)`
/// only; the per-group helpers are internal for focus.
extension CameraSettings {
    static func apply(_ s: CameraSettings, to device: AVCaptureDevice, log: Bool = true) {
        do { try device.lockForConfiguration() } catch {
            applog("stream", "camera settings: lockForConfiguration failed: \(error.localizedDescription)", error: true)
            return
        }
        defer { device.unlockForConfiguration() }
        var applied: [String] = []
        var skipped: [String] = []

        applyZoom(s, to: device, applied: &applied)
        applyFocus(s, to: device, applied: &applied, skipped: &skipped)
        applyExposure(s, to: device, applied: &applied, skipped: &skipped)
        applyWhiteBalance(s, to: device, applied: &applied, skipped: &skipped)
        applyImage(s, to: device, applied: &applied, skipped: &skipped)

        if log {
            applog("stream", "camera settings: \(applied.joined(separator: " "))"
                + (skipped.isEmpty ? "" : " -- unsupported on this camera, skipped: \(skipped.joined(separator: ", "))"))
        }
    }

    private static func applyZoom(_ s: CameraSettings, to device: AVCaptureDevice, applied: inout [String]) {
        let zoom = clamped(s.zoom, min: device.minAvailableVideoZoomFactor, max: min(device.maxAvailableVideoZoomFactor, maxUsableZoomFactor))
        device.videoZoomFactor = zoom
        applied.append("zoom=\(String(format: "%.2f", zoom))x")
    }

    private static func applyFocus(_ s: CameraSettings, to device: AVCaptureDevice, applied: inout [String], skipped: inout [String]) {
        switch s.focusMode {
        case "manual":
            if device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: Float(clamped(s.lensPosition, min: 0, max: 1)))
                applied.append("focus=manual(\(s.lensPosition))")
            } else { skipped.append("manual focus") }
        case "auto":
            if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus; applied.append("focus=auto") }
            else { skipped.append("auto focus") }
        default:
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus; applied.append("focus=continuous") }
            else { skipped.append("continuous focus") }
        }
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = s.smoothAutoFocus
            applied.append("smoothAF=\(s.smoothAutoFocus)")
        } else { skipped.append("smooth autofocus") }
        // No documented isFaceDrivenAutoFocusSupported flag (checked Apple's docs directly) -- gate on
        // continuous AF support instead, the mode this actually affects.
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = false
            device.isFaceDrivenAutoFocusEnabled = s.faceDrivenAutoFocus
            applied.append("faceAF=\(s.faceDrivenAutoFocus)")
        }
    }

    private static func applyExposure(_ s: CameraSettings, to device: AVCaptureDevice, applied: inout [String], skipped: inout [String]) {
        if s.exposureManual, device.isExposureModeSupported(.custom) {
            let iso = Float(clamped(s.manualISO, min: Double(device.activeFormat.minISO), max: Double(device.activeFormat.maxISO)))
            let seconds = clampedSeconds(s.manualShutterMs, minSeconds: device.activeFormat.minExposureDuration.seconds, maxSeconds: device.activeFormat.maxExposureDuration.seconds)
            device.setExposureModeCustom(duration: CMTime(seconds: seconds, preferredTimescale: 1_000_000), iso: iso)
            applied.append("exposure=manual(iso=\(Int(iso)),\(String(format: "%.4f", seconds))s)")
        } else if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
            let bias = Float(clamped(s.exposureBiasEV, min: Double(device.minExposureTargetBias), max: Double(device.maxExposureTargetBias)))
            device.setExposureTargetBias(bias)
            applied.append("exposure=auto(ev=\(bias))")
        } else { skipped.append("exposure") }
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = s.lowLightBoost
            applied.append("lowLightBoost=\(s.lowLightBoost)")
        } else { skipped.append("low-light boost") }
    }

    private static func applyWhiteBalance(_ s: CameraSettings, to device: AVCaptureDevice, applied: inout [String], skipped: inout [String]) {
        if s.whiteBalanceManual, device.isWhiteBalanceModeSupported(.locked) {
            let tt = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(s.whiteBalanceTemperature), tint: Float(s.whiteBalanceTint))
            let gains = clampedGains(device.deviceWhiteBalanceGains(for: tt), max: device.maxWhiteBalanceGain)
            device.setWhiteBalanceModeLocked(with: gains)
            applied.append("wb=manual(\(Int(s.whiteBalanceTemperature))K)")
        } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
            applied.append("wb=auto")
        } else { skipped.append("white balance") }
    }

    private static func applyImage(_ s: CameraSettings, to device: AVCaptureDevice, applied: inout [String], skipped: inout [String]) {
        if s.hdr != "auto" {
            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = s.hdr == "on"
                applied.append("hdr=\(s.hdr)")
            } else { skipped.append("HDR") }
        }

        if device.hasTorch {
            if s.torchLevel > 0, device.isTorchModeSupported(.on) {
                do { try device.setTorchModeOn(level: Float(clamped(s.torchLevel, min: 0.01, max: 1))) }
                catch { skipped.append("torch (\(error.localizedDescription))") }
                applied.append("torch=\(String(format: "%.0f%%", s.torchLevel * 100))")
            } else if device.isTorchModeSupported(.off) {
                device.torchMode = .off
            }
        } else { skipped.append("torch") }

        if device.isGeometricDistortionCorrectionSupported {
            device.isGeometricDistortionCorrectionEnabled = s.geometricDistortionCorrection
            applied.append("gdc=\(s.geometricDistortionCorrection)")
        } else { skipped.append("geometric distortion correction") }
    }
}
