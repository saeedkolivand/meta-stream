package com.saeedkolivand.metastream.streaming

import android.graphics.SurfaceTexture
import android.hardware.usb.UsbDevice
import android.view.Surface
import com.herohan.uvcapp.CameraHelper
import com.herohan.uvcapp.ICameraHelper
import com.pedro.encoder.input.sources.OrientationConfig
import com.pedro.encoder.input.sources.OrientationForced
import com.pedro.encoder.input.sources.video.VideoSource
import com.saeedkolivand.metastream.core.applog

/**
 * USB (UVC) camera, e.g. a DJI Osmo Action in webcam mode. RootEncoder's CameraUvcSource ignores the requested size and
 * opens the camera at UVCAndroid's default (often 720p); this one opens the largest 16:9 format up to the stream's
 * height, preferring one that offers the stream's fps, so a 4K-capable camera really sends 4K when 4K is configured.
 */
class UvcSource : VideoSource() {
    private var helper: ICameraHelper? = null
    private var surface: Surface? = null
    private var running = false
    private var wantHeight = 1080
    private var wantFps = 30

    override fun create(width: Int, height: Int, fps: Int, rotation: Int): Boolean {
        // prepareVideo swaps width/height for portrait; a UVC camera is always landscape, so the short side is the height.
        wantHeight = minOf(width, height)
        wantFps = fps
        return true
    }

    override fun start(surfaceTexture: SurfaceTexture) {
        this.surfaceTexture = surfaceTexture
        if (running) return
        surface = Surface(surfaceTexture)
        helper = CameraHelper().also { it.setStateCallback(callback) }
        running = true
    }

    override fun stop() {
        surface?.let { helper?.removeSurface(it) }
        surface?.release()
        surface = null
        helper?.release()
        helper = null
        running = false
    }

    override fun release() {}

    override fun isRunning() = running

    override fun getOrientationConfig() = OrientationConfig(forced = OrientationForced.LANDSCAPE)

    private val callback = object : ICameraHelper.StateCallback {
        override fun onAttach(device: UsbDevice) {
            helper?.selectDevice(device)
        }

        override fun onDeviceOpen(device: UsbDevice, isFirstOpen: Boolean) {
            val h = helper ?: return
            val sizes = h.supportedSizeList.orEmpty()
            val pick = pickSize(sizes.map { Triple(it.width, it.height, it.fpsList.orEmpty()) }, wantHeight, wantFps)
            val size = pick?.let { sizes[it] }
            applog(
                "stream",
                "usb camera ${device.productName ?: "unknown"} active=${size?.let { "${it.width}x${it.height}" } ?: "default"} " +
                    "offered=${sizes.map { "${it.width}x${it.height}" }.distinct()}"
            )
            if (size == null) {
                h.openCamera()
                return
            }
            if (wantFps in size.fpsList.orEmpty()) size.fps = wantFps
            // The GL pipeline samples the texture at its buffer size: match it to the camera so nothing is down-scaled twice.
            surfaceTexture?.setDefaultBufferSize(size.width, size.height)
            h.openCamera(size)
        }

        override fun onCameraOpen(device: UsbDevice) {
            helper?.startPreview()
            surface?.let { helper?.addSurface(it, false) }
        }

        override fun onCameraClose(device: UsbDevice) {}

        override fun onDeviceClose(device: UsbDevice) {}

        override fun onDetach(device: UsbDevice) {}

        override fun onCancel(device: UsbDevice) {}
    }
}

/**
 * Index of the best (width, height, fpsList) for a stream [wantHeight] tall at [wantFps]: 16:9 only, height <= wanted,
 * those offering [wantFps] first, then the tallest. Null when the camera lists no 16:9 format at or below the target.
 */
internal fun pickSize(sizes: List<Triple<Int, Int, List<Int>>>, wantHeight: Int, wantFps: Int): Int? {
    val fits = sizes.indices.filter { i -> sizes[i].let { (w, h, _) -> w * 9 == h * 16 && h <= wantHeight } }
    val withFps = fits.filter { wantFps in sizes[it].third }
    return (withFps.ifEmpty { fits }).maxByOrNull { sizes[it].second }
}
