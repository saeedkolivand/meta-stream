package com.saeedkolivand.metastream.camera

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FaceCamLayoutTest {
    private val eps = 0.01f

    @Test fun parseDefaultsOnNullAndGarbage() {
        assertEquals(FaceCamOptions(), FaceCamOptions.parse(null, null, null))
        assertEquals(FaceCamOptions(), FaceCamOptions.parse("middle", "xl", "star"))
        assertEquals(FaceCamOptions("bottomLeft", "l", "circle"), FaceCamOptions.parse("bottomLeft", "l", "circle"))
    }

    @Test fun portraitRoundedTopRight() {
        val r = faceRect(720, 1280, FaceCamOptions())
        assertEquals(216f, r.w, eps)
        assertEquals(216f * 16 / 9, r.h, eps)
        assertEquals(720 - 216 - 28.8f, r.x, eps)
        assertEquals(28.8f, r.y, eps)
    }

    @Test fun landscapeRoundedIsWide() {
        val r = faceRect(1280, 720, FaceCamOptions(size = "s"))
        assertEquals(720 * 0.22f, r.h, eps)
        assertEquals(r.h * 16 / 9, r.w, eps)
    }

    @Test fun circleIsSquareInBottomLeft() {
        val r = faceRect(720, 1280, FaceCamOptions("bottomLeft", "l", "circle"))
        assertEquals(r.w, r.h, eps)
        assertEquals(288f, r.w, eps)
        assertEquals(28.8f, r.x, eps)
        assertEquals(1280 - 288 - 28.8f, r.y, eps)
        assertEquals(144f, faceRadius(r, "circle"), eps)
    }

    @Test fun roundedRadiusIsTwelvePercentOfShortSide() {
        val r = faceRect(720, 1280, FaceCamOptions())
        assertEquals(216f * 0.12f, faceRadius(r, "rounded"), eps)
    }

    @Test fun hitTest() {
        val r = faceRect(720, 1280, FaceCamOptions())
        assertTrue(r.contains(r.x + 1, r.y + 1))
        assertFalse(r.contains(0f, 0f))
    }

    private val sets = setOf(setOf("0", "1"), setOf("2", "3"))
    private val front = { id: String -> id == "1" || id == "3" }
    private val back = { id: String -> id == "0" || id == "2" }

    @Test fun partnerFollowsTheBackCamera() {
        assertEquals("1", frontPartner(sets, "0", front, back))
        assertEquals("3", frontPartner(sets, "2", front, back))
        assertNull(frontPartner(sets, "9", front, back))
    }

    @Test fun anyPairWithoutBackId() {
        assertEquals("1", frontPartner(sets, null, front, back))
        assertNull(frontPartner(setOf(setOf("0")), null, front, back))
    }
}
