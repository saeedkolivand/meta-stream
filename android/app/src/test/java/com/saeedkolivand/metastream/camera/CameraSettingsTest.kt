package com.saeedkolivand.metastream.camera

import com.saeedkolivand.metastream.ui.moved
import org.junit.Assert.assertEquals
import org.junit.Test

class CameraSettingsTest {
    @Test fun validOrderParsesInPlace() {
        assertEquals(listOf(LiveControl.Zoom, LiveControl.Torch), LiveControl.parse("zoom,torch"))
    }

    @Test fun unknownTokensAreDropped() {
        assertEquals(listOf(LiveControl.Zoom, LiveControl.Torch), LiveControl.parse("zoom,bogus,torch"))
        assertEquals(listOf(LiveControl.Zoom), LiveControl.parse(" zoom ,zoom"))
    }

    @Test fun emptyOrAllUnknownFallsBackToDefault() {
        assertEquals(LiveControl.defaultOrder, LiveControl.parse(""))
        assertEquals(LiveControl.defaultOrder, LiveControl.parse("nope,also-nope"))
    }

    @Test fun customOrderSurvivesStorage() {
        val custom = listOf(LiveControl.Torch, LiveControl.Zoom, LiveControl.Mirror)
        assertEquals(custom, LiveControl.parse(LiveControl.serialize(custom)))
    }

    @Test fun storageKeysMatchIos() {
        assertEquals("lens,zoom,exposure,torch,whiteBalanceLock,stabilization,mirror", LiveControl.serialize(LiveControl.defaultOrder))
    }

    @Test fun settingsRoundTrip() {
        val s =
            CameraSettings(
                zoom = 2.5f,
                exposureManual = true,
                iso = 400f,
                stabilization = "ois",
                mirrored = true,
                order = listOf(LiveControl.Zoom)
            )
        assertEquals(s, CameraSettings.fromJson(s.toJson()))
    }

    @Test fun missingOrCorruptJsonKeepsDefaults() {
        assertEquals(CameraSettings(), CameraSettings.fromJson(""))
        assertEquals(CameraSettings(), CameraSettings.fromJson("{not json"))
        assertEquals(1f, CameraSettings.fromJson("{\"hdr\":\"on\"}").zoom, 0f) // absent zoom must not become 0x
    }

    @Test fun reorderingMovesOneItem() {
        assertEquals(listOf(2, 1, 3), listOf(1, 2, 3).moved(1, 0))
        assertEquals(listOf(1, 3, 2), listOf(1, 2, 3).moved(1, 2))
    }

    @Test fun reorderingPastTheEndsIsANoOp() {
        assertEquals(listOf(1, 2, 3), listOf(1, 2, 3).moved(0, -1))
        assertEquals(listOf(1, 2, 3), listOf(1, 2, 3).moved(2, 3))
    }
}
