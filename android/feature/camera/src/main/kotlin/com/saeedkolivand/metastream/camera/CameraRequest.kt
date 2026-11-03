package com.saeedkolivand.metastream.camera

import android.hardware.camera2.CameraMetadata as M
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.ColorSpaceTransform
import android.hardware.camera2.params.MeteringRectangle
import android.hardware.camera2.params.RggbChannelVector
import kotlin.math.roundToInt

/** Where the user last tapped (sensor-normalised) and whether AE/AF are frozen there. */
data class Meter(val x: Float, val y: Float, val locked: Boolean)

private const val NS_PER_MS = 1_000_000L

private fun CaptureRequest.Builder.exposure(s: CameraSettings, c: CameraCaps, aeLock: Boolean) {
    if (s.exposureManual && c.manualSensor) {
        set(CaptureRequest.CONTROL_AE_MODE, M.CONTROL_AE_MODE_OFF)
        set(CaptureRequest.SENSOR_SENSITIVITY, clamp(s.iso, c.isoMin, c.isoMax).roundToInt())
        set(CaptureRequest.SENSOR_EXPOSURE_TIME, (clamp(s.shutterMs, c.shutterMinMs, c.shutterMaxMs) * NS_PER_MS).toLong())
        return
    }
    val boost = s.lowLight && c.lowLight
    set(CaptureRequest.CONTROL_AE_MODE, if (boost) M.CONTROL_AE_MODE_ON_LOW_LIGHT_BOOST_BRIGHTNESS_PRIORITY else M.CONTROL_AE_MODE_ON)
    // Bias only moves auto exposure; manual ISO/shutter ignores it, same as iOS.
    val index = if (c.evStep > 0f) (clamp(s.biasEv, c.evMin, c.evMax) / c.evStep).roundToInt() else 0
    set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, index)
    set(CaptureRequest.CONTROL_AE_LOCK, aeLock && c.aeLock)
}

private fun CaptureRequest.Builder.whiteBalance(s: CameraSettings, c: CameraCaps, last: ColorSpaceTransform?) {
    if (s.wbManual && c.manualWb && last != null) {
        // Gains need the HAL's own colour matrix, captured from auto frames; without it manual WB would tint wrongly.
        val g = kelvinToGains(s.wbKelvin, s.wbTint)
        set(CaptureRequest.CONTROL_AWB_MODE, M.CONTROL_AWB_MODE_OFF)
        set(CaptureRequest.COLOR_CORRECTION_MODE, M.COLOR_CORRECTION_MODE_TRANSFORM_MATRIX)
        set(CaptureRequest.COLOR_CORRECTION_TRANSFORM, last)
        set(CaptureRequest.COLOR_CORRECTION_GAINS, RggbChannelVector(g[0], g[1], g[2], g[3]))
        return
    }
    set(CaptureRequest.CONTROL_AWB_MODE, M.CONTROL_AWB_MODE_AUTO)
    set(CaptureRequest.COLOR_CORRECTION_MODE, M.COLOR_CORRECTION_MODE_FAST)
    set(CaptureRequest.CONTROL_AWB_LOCK, s.wbLock && c.awbLock)
}

private fun CaptureRequest.Builder.focus(s: CameraSettings, c: CameraCaps, frozen: Boolean) {
    val mode = when {
        s.focusMode == "manual" && c.manualFocus -> M.CONTROL_AF_MODE_OFF
        frozen || s.focusMode == "auto" -> M.CONTROL_AF_MODE_AUTO
        s.smoothAf -> M.CONTROL_AF_MODE_CONTINUOUS_VIDEO
        else -> M.CONTROL_AF_MODE_CONTINUOUS_PICTURE
    }
    // Devices without the mode fall back to what they have rather than rejecting the whole request.
    set(CaptureRequest.CONTROL_AF_MODE, if (c.afModes.isEmpty() || mode in c.afModes) mode else M.CONTROL_AF_MODE_OFF)
    if (mode == M.CONTROL_AF_MODE_OFF && c.manualFocus) {
        set(CaptureRequest.LENS_FOCUS_DISTANCE, (1f - clamp(s.lensPosition, 0f, 1f)) * c.minFocusDiopter)
    }
    set(
        CaptureRequest.STATISTICS_FACE_DETECT_MODE,
        if (s.faceAf &&
            c.faceDetect
        ) {
            M.STATISTICS_FACE_DETECT_MODE_SIMPLE
        } else {
            M.STATISTICS_FACE_DETECT_MODE_OFF
        }
    )
}

private fun CaptureRequest.Builder.regions(c: CameraCaps, meter: Meter?) {
    if (meter == null || c.activeW == 0) return
    val b = meteringBox(meter.x, meter.y, c.activeW, c.activeH)
    val region = arrayOf(MeteringRectangle(b[0], b[1], b[2], b[3], MeteringRectangle.METERING_WEIGHT_MAX))
    if (c.afRegions) set(CaptureRequest.CONTROL_AF_REGIONS, region)
    if (c.aeRegions) set(CaptureRequest.CONTROL_AE_REGIONS, region)
}

/**
 * Writes every key this app manages from [s]. Always sets all of them (a stale value from the previous apply would
 * otherwise stick), and leaves RootEncoder's own keys (target surface, fps range) alone.
 */
fun CaptureRequest.Builder.applyCamera(s: CameraSettings, c: CameraCaps, meter: Meter?, wbMatrix: ColorSpaceTransform?, trigger: Boolean) {
    set(CaptureRequest.CONTROL_ZOOM_RATIO, clamp(s.zoom, c.zoomMin, c.zoomMax))
    val hdr = s.hdr == "on" && c.hdr
    set(CaptureRequest.CONTROL_MODE, if (hdr) M.CONTROL_MODE_USE_SCENE_MODE else M.CONTROL_MODE_AUTO)
    if (hdr) set(CaptureRequest.CONTROL_SCENE_MODE, M.CONTROL_SCENE_MODE_HDR)
    val locked = meter?.locked == true
    exposure(s, c, locked)
    whiteBalance(s, c, wbMatrix)
    focus(s, c, locked)
    regions(c, meter)
    set(CaptureRequest.CONTROL_AF_TRIGGER, if (trigger) M.CONTROL_AF_TRIGGER_START else M.CONTROL_AF_TRIGGER_IDLE)

    val torchOn = s.torch > 0f && c.torch
    set(CaptureRequest.FLASH_MODE, if (torchOn) M.FLASH_MODE_TORCH else M.FLASH_MODE_OFF)
    if (torchOn && c.torchMaxLevel > 1) {
        set(CaptureRequest.FLASH_STRENGTH_LEVEL, (s.torch * c.torchMaxLevel).roundToInt().coerceIn(1, c.torchMaxLevel))
    }
    // EIS and OIS are exclusive here: some HALs refuse the request when both are on.
    set(
        CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
        if (s.stabilization ==
            "standard"
        ) {
            M.CONTROL_VIDEO_STABILIZATION_MODE_ON
        } else {
            M.CONTROL_VIDEO_STABILIZATION_MODE_OFF
        }
    )
    set(
        CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
        if (s.stabilization ==
            "ois"
        ) {
            M.LENS_OPTICAL_STABILIZATION_MODE_ON
        } else {
            M.LENS_OPTICAL_STABILIZATION_MODE_OFF
        }
    )
    if (c.distortion.isNotEmpty()) {
        val on = if (M.DISTORTION_CORRECTION_MODE_HIGH_QUALITY in
            c.distortion
        ) {
            M.DISTORTION_CORRECTION_MODE_HIGH_QUALITY
        } else {
            M.DISTORTION_CORRECTION_MODE_FAST
        }
        set(CaptureRequest.DISTORTION_CORRECTION_MODE, if (s.distortion) on else M.DISTORTION_CORRECTION_MODE_OFF)
    }
}
