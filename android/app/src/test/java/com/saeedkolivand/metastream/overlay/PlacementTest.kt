package com.saeedkolivand.metastream.overlay

import org.junit.Assert.assertEquals
import org.junit.Test

class PlacementTest {
    private fun layer(
        x: Float = 0f,
        y: Float = 0f,
        sx: Float = 1f,
        sy: Float = 1f,
        align: Int = 5,
        boundsType: Int = 0,
        bw: Float = 0f,
        bh: Float = 0f,
        boundsAlign: Int = 0
    ) = Layer(LayerType.Image, "n", true, x, y, sx, sy, align, boundsType, bw, bh, boundsAlign, 0f, listOf(0, 0, 0, 0), emptyMap())

    @Test fun topLeftScaled() {
        val b = place(layer(10f, 20f, 2f, 2f), 100f, 50f)
        assertEquals(Box(10f, 20f, 200f, 100f), b)
    }

    @Test fun centerAligned() {
        val b = place(layer(960f, 540f, align = 0), 200f, 100f)
        assertEquals(Box(860f, 490f, 200f, 100f), b)
    }

    @Test fun boundsScaleInnerCentersInBox() {
        val b = place(layer(0f, 0f, boundsType = 2, bw = 400f, bh = 400f), 200f, 100f)
        assertEquals(Box(0f, 100f, 400f, 200f), b)
    }

    @Test fun boundsStretchFillsBox() {
        assertEquals(Box(0f, 0f, 400f, 300f), place(layer(boundsType = 1, bw = 400f, bh = 300f), 200f, 100f))
    }

    @Test fun landscapeCanvasIsCenteredInPortraitOutput() {
        val f = fit(1920, 1080, 720, 1280)
        assertEquals(0.375f, f.scale, 0.0001f)
        assertEquals(0f, f.offX, 0.001f)
        assertEquals((1280 - 405f) / 2, f.offY, 0.01f)
        val full = f.apply(Box(0f, 0f, 1920f, 1080f))
        assertEquals(720f, full.w, 0.01f)
    }
}
