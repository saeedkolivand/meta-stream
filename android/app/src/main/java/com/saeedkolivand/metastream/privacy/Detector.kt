package com.saeedkolivand.metastream.privacy

import android.graphics.Bitmap
import android.graphics.Rect
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class Targets(val faces: Boolean, val text: Boolean, val barcodes: Boolean)

/** One pass: face/barcode boxes, plus text boxes when text ran this pass (null = skipped, carry the last ones). */
class Found(val other: List<Box>, val text: List<Box>?)

/**
 * ML Kit with the bundled models: they work offline mid-stream and without Play services, at the cost of a few MB of APK
 * (the Play-services variants download on first use and can't be trusted to be there when the network drops).
 * Text recognition (not just text detection) is what finds licence plates, house numbers and badges, as on iOS.
 */
class Detector(private val rotation: Int) {
    private val faces by lazy {
        FaceDetection.getClient(
            FaceDetectorOptions.Builder().setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setMinFaceSize(MIN_FACE).build()
        )
    }
    private val text by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
    private val barcodes by lazy { BarcodeScanning.getClient() }

    /** Calls [done] with the boxes (in bitmap space), or null if any enabled detector failed, so the caller can fail closed. */
    fun detect(frame: Bitmap, want: Targets, done: (Found?) -> Unit) {
        val img = InputImage.fromBitmap(frame, rotation)
        val (uw, uh) = if (rotation % 180 == 0) frame.width to frame.height else frame.height to frame.width
        fun norm(r: Rect?) = r?.let { uprightToImage(normalize(it.left, it.top, it.right, it.bottom, uw, uh), rotation) }
        val jobs = mutableListOf<Task<List<Box>>>()
        if (want.faces) jobs += faces.process(img).continueWith { t -> t.result.mapNotNull { norm(it.boundingBox) } }
        if (want.barcodes) jobs += barcodes.process(img).continueWith { t -> t.result.mapNotNull { norm(it.boundingBox) } }
        val textJob = if (want.text) {
            text.process(img).continueWith { t -> t.result.textBlocks.flatMap { it.lines }.mapNotNull { norm(it.boundingBox) } }
        } else {
            null
        }
        Tasks.whenAllComplete(jobs + listOfNotNull(textJob)).addOnCompleteListener {
            val ok = jobs.all { it.isSuccessful } && textJob?.isSuccessful != false
            done(if (ok) Found(jobs.flatMap { it.result }, textJob?.result) else null)
        }
    }

    /** Loads the enabled models up front: the first getClient is slow and must not happen on the GL thread. */
    fun warm(want: Targets) {
        if (want.faces) faces
        if (want.text) text
        if (want.barcodes) barcodes
    }

    private companion object {
        const val MIN_FACE = 0.04f // default 0.1 misses a face further than a few metres
    }
}
