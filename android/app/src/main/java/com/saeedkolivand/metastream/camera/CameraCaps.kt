package com.saeedkolivand.metastream.camera

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata as M
import kotlin.math.min

/** What the open camera can actually do; the UI greys out or hides controls against this (iOS CameraCapabilities). */
data class CameraCaps(
    val front: Boolean = false,
    val sensorOrientation: Int = 90,
    val activeW: Int = 0,
    val activeH: Int = 0,
    val zoomMin: Float = 1f,
    val zoomMax: Float = 1f,
    val evMin: Float = 0f,
    val evMax: Float = 0f,
    val evStep: Float = 0f,
    val torch: Boolean = false,
    val torchMaxLevel: Int = 1,
    val manualSensor: Boolean = false,
    val isoMin: Float = 100f,
    val isoMax: Float = 100f,
    val shutterMinMs: Float = 1f,
    val shutterMaxMs: Float = 1f,
    val manualWb: Boolean = false,
    val awbLock: Boolean = false,
    val aeLock: Boolean = false,
    val minFocusDiopter: Float = 0f,
    val afModes: Set<Int> = emptySet(),
    val eis: Boolean = false,
    val ois: Boolean = false,
    val hdr: Boolean = false,
    val lowLight: Boolean = false,
    val distortion: IntArray = IntArray(0),
    val faceDetect: Boolean = false,
    val afRegions: Boolean = false,
    val aeRegions: Boolean = false,
    val lenses: List<LensOption> = emptyList()
) {
    val zoomable get() = zoomMax > zoomMin
    val manualFocus get() = minFocusDiopter > 0f
    val stabilizationModes get() = listOf("off") + listOfNotNull("standard".takeIf { eis }, "ois".takeIf { ois })

    companion object {
        /** Reads [id]'s characteristics; null when the id vanished (camera unplugged, permission revoked). */
        fun probe(context: Context, id: String): CameraCaps? = try {
            val cm = context.getSystemService(CameraManager::class.java)
            read(cm, id, cm.getCameraCharacteristics(id))
        } catch (e: IllegalArgumentException) {
            null
        } catch (e: android.hardware.camera2.CameraAccessException) {
            null
        }

        private fun read(cm: CameraManager, id: String, c: CameraCharacteristics): CameraCaps {
            val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)?.toSet().orEmpty()
            val active = c.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            val zoom = c.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
            val ev = c.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
            val step = c.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP)?.toFloat() ?: 0f
            val iso = c.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
            val exp = c.get(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE)
            val zMin = zoom?.lower ?: 1f
            val zMax = min(zoom?.upper ?: 1f, MAX_USABLE_ZOOM)
            return CameraCaps(
                front = c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT,
                sensorOrientation = c.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90,
                activeW = active?.width() ?: 0,
                activeH = active?.height() ?: 0,
                zoomMin = zMin,
                zoomMax = zMax,
                evMin = (ev?.lower ?: 0) * step,
                evMax = (ev?.upper ?: 0) * step,
                evStep = step,
                torch = c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true,
                torchMaxLevel = c.get(CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL) ?: 1,
                manualSensor = M.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR in caps && iso != null && exp != null,
                isoMin = iso?.lower?.toFloat() ?: 100f,
                isoMax = iso?.upper?.toFloat() ?: 100f,
                // Capped at 1/30s: slower than the frame rate would stall the stream.
                shutterMinMs = (exp?.lower ?: 1_000_000L) / 1e6f,
                shutterMaxMs = min((exp?.upper ?: 1_000_000L) / 1e6f, 33.3f),
                manualWb = M.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_POST_PROCESSING in caps,
                awbLock = c.get(CameraCharacteristics.CONTROL_AWB_LOCK_AVAILABLE) == true,
                aeLock = c.get(CameraCharacteristics.CONTROL_AE_LOCK_AVAILABLE) == true,
                minFocusDiopter = c.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f,
                afModes = c.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.toSet().orEmpty(),
                eis =
                c.get(
                    CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES
                )?.contains(M.CONTROL_VIDEO_STABILIZATION_MODE_ON) ==
                    true,
                ois =
                c.get(
                    CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION
                )?.contains(M.LENS_OPTICAL_STABILIZATION_MODE_ON) ==
                    true,
                hdr = c.get(CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES)?.contains(M.CONTROL_SCENE_MODE_HDR) == true,
                lowLight =
                c.get(
                    CameraCharacteristics.CONTROL_AE_AVAILABLE_MODES
                )?.contains(M.CONTROL_AE_MODE_ON_LOW_LIGHT_BOOST_BRIGHTNESS_PRIORITY) ==
                    true,
                distortion = c.get(CameraCharacteristics.DISTORTION_CORRECTION_AVAILABLE_MODES) ?: IntArray(0),
                faceDetect =
                c.get(
                    CameraCharacteristics.STATISTICS_INFO_AVAILABLE_FACE_DETECT_MODES
                )?.contains(M.STATISTICS_FACE_DETECT_MODE_SIMPLE) ==
                    true,
                afRegions = (c.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) ?: 0) > 0,
                aeRegions = (c.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE) ?: 0) > 0,
                lenses = lenses(cm, c, zMin, zMax)
            )
        }

        /** Physical lenses behind a logical multi-camera, as equivalent focal lengths; a plain camera yields no chips. */
        private fun lenses(cm: CameraManager, logical: CameraCharacteristics, zMin: Float, zMax: Float): List<LensOption> {
            val equivs = logical.physicalCameraIds.mapNotNull { pid ->
                val p = cm.getCameraCharacteristics(pid)
                val focal = p.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull()
                val width = p.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)?.width
                if (focal != null && width != null && width > 0f) equivFocal(focal, width) else null
            }
            return lensOptions(equivs, zMin, zMax)
        }
    }
}
