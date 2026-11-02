package com.saeedkolivand.metastream.overlay

import android.graphics.Bitmap
import android.graphics.RectF

/**
 * One look of a widget, drawn by [SpriteFilter] on the GL thread. [items] is pure: the same [t] (seconds since [epochNanos])
 * always gives the same picture, so a moving scene needs no CPU render per frame. A still scene builds once. Rects are in the
 * widget's natural units.
 */
internal class GpuScene(
    val width: Float,
    val height: Float,
    val moving: Boolean,
    val epochNanos: Long = System.nanoTime(),
    val topFade: Float = 0f,
    // units are output px over the whole frame, not the widget box (donation alerts)
    val canvas: Boolean = false,
    private val build: (Float) -> List<Item>
) {
    private val fixed = if (moving) null else build(0f)

    fun items(t: Float): List<Item> = fixed ?: build(t)
}

/**
 * One quad: a bitmap, or a solid [color] when [image] is null. [color] also tints an image (white leaves it unchanged).
 * [rect] and [clip] are both in scene units (the same space); [radius]/[clipRadius] round them.
 */
internal class Item(
    val rect: RectF,
    val image: Bitmap? = null,
    val color: Int = 0xFFFFFFFF.toInt(),
    val alpha: Float = 1f,
    val radius: Float = 0f,
    val clip: RectF? = null,
    val clipRadius: Float = 0f,
    // degrees clockwise about the rect's centre
    val rotation: Float = 0f
)
