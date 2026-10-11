package com.saeedkolivand.metastream.camera

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CameraMathTest {
    @Test fun clampStaysInRange() {
        assertEquals(3f, clamp(5f, 1f, 3f), 0f)
        assertEquals(1f, clamp(0.2f, 1f, 3f), 0f)
        assertEquals(2f, clamp(2f, 1f, 3f), 0f)
        assertEquals(1f, clamp(5f, 1f, 1f), 0f) // unzoomable camera: min == max
    }

    @Test fun multiplierLabelsRoundLikeIos() {
        assertEquals("3", multiplierLabel(2.98f))
        assertEquals("0.5", multiplierLabel(0.52f))
        assertEquals("1", multiplierLabel(1.02f))
        assertEquals("1.5", multiplierLabel(1.4f))
        assertEquals("5", multiplierLabel(4.7f))
    }

    // Pixel-like triple: ultra-wide, main, 5x telephoto (35mm-equivalent focal lengths).
    @Test fun lensChipsWithUltraWide() {
        val chips = lensOptions(listOf(121f, 13f, 24f), 0.5f, 30f)
        assertEquals(listOf("0.5", "1", "5"), chips.map { it.label })
        assertEquals(listOf(0.5f, 1f, 5f), chips.map { it.zoom })
    }

    @Test fun lensChipsWithoutUltraWide() {
        val chips = lensOptions(listOf(24f, 70f), 1f, 30f)
        assertEquals(listOf("1", "3"), chips.map { it.label })
    }

    @Test fun singleLensHasNoChips() {
        assertTrue(lensOptions(listOf(24f), 1f, 1f).isEmpty())
        assertTrue(lensOptions(emptyList(), 1f, 1f).isEmpty())
    }

    @Test fun lensChipsClampToTheCamerasZoomRange() {
        // Zoom range tops out at 3x, so a 5x lens cannot promise more than that.
        val chips = lensOptions(listOf(24f, 120f), 1f, 3f)
        assertEquals(3f, chips.last().zoom, 0f)
    }

    @Test fun equivalentFocalUsesSensorWidth() {
        assertEquals(24f, equivFocal(6.9f, 10.35f), 0.01f)
    }

    @Test fun tapMapsLikeIosDevicePoint() {
        // Portrait phone, back camera: sensor orientation 90, display 0 -> turned 90 degrees clockwise.
        assertEquals(0f to 1f, viewToSensor(0f, 0f, 90, false)) // iOS .portrait: view top-left -> (0, 1)
        assertEquals(0.5f to 0.5f, viewToSensor(0.5f, 0.5f, 90, false))
        assertEquals(1f to 0f, viewToSensor(0f, 0f, 270, false)) // portraitUpsideDown
        assertEquals(0f to 0f, viewToSensor(0f, 0f, 0, false)) // landscapeRight
        assertEquals(1f to 1f, viewToSensor(0f, 0f, 180, false)) // landscapeLeft
    }

    @Test fun mirrorFlipsTheTapX() {
        // Mirroring happens on screen, before the rotation back to the sensor: (0,0) shows what sits at (1,0).
        assertEquals(0f to 0f, viewToSensor(0f, 0f, 90, true))
        assertEquals(0f to 1f, viewToSensor(1f, 0f, 90, true))
    }

    @Test fun tapRotationWrapsNegative() {
        assertEquals(viewToSensor(0.2f, 0.7f, 270, false), viewToSensor(0.2f, 0.7f, -90, false))
    }

    @Test fun meteringBoxStaysInsideTheArray() {
        val corner = meteringBox(0f, 0f, 4000, 3000)
        assertArrayEquals(intArrayOf(0, 0, 450, 450), corner)
        val far = meteringBox(1f, 1f, 4000, 3000)
        assertArrayEquals(intArrayOf(3550, 2550, 450, 450), far)
    }

    @Test fun warmLightNeedsMoreBlueGain() {
        val warm = kelvinToGains(2800f, 0f)
        val cool = kelvinToGains(9000f, 0f)
        assertTrue(warm[3] > warm[0])
        assertTrue(cool[0] > cool[3])
        assertEquals(1f, warm.min(), 0.0001f) // smallest gain normalised to 1
    }

    @Test fun tintMovesGreenOnly() {
        val neutral = kelvinToGains(5500f, 0f)
        val magenta = kelvinToGains(5500f, 100f)
        assertTrue(magenta[1] / magenta[0] < neutral[1] / neutral[0]) // magenta = less green relative to red
        assertTrue(magenta[1] / magenta[3] < neutral[1] / neutral[3])
        assertEquals(magenta[1], magenta[2], 0f)
    }

    @Test fun shutterLabelIsAFraction() {
        assertEquals("1/60s", shutterLabel(16.7f))
        assertEquals("1/30s", shutterLabel(33.3f))
        assertEquals("1/1s", shutterLabel(5000f))
    }

    @Test fun levelPhoneReadsZeroRoll() {
        assertEquals(0f, rollDegrees(0f, 9.8f, 0), 0.01f)
        assertTrue(isLevel(rollDegrees(0.1f, 9.8f, 0)))
    }

    @Test fun clockwiseTiltIsPositive() {
        // Tilted 30 degrees clockwise: gravity reaction has -x component.
        val roll = rollDegrees(-4.9f, 8.49f, 0)
        assertEquals(30f, roll, 0.1f)
        assertFalse(isLevel(roll))
    }

    @Test fun landscapeRollUsesScreenAxes() {
        // Display rotation 90 (phone turned counter-clockwise): "up" is the device's +x axis.
        assertEquals(0f, rollDegrees(9.8f, 0f, 90), 0.01f)
        assertEquals(0f, rollDegrees(-9.8f, 0f, 270), 0.01f)
        assertEquals(30f, rollDegrees(8.49f, 4.9f, 90), 0.1f)
    }
}
