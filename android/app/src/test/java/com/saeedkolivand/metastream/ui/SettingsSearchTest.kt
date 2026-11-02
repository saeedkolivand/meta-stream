package com.saeedkolivand.metastream.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SettingsSearchTest {
    private val words = "Lens & zoom: lens zoom; Face cam: dual camera front"

    @Test
    fun hitsShowTheirSubSection() {
        assertEquals("Camera", searchHit("Camera", words, "cam"))
        assertEquals("Camera › Face cam", searchHit("Camera", words, "dual"))
        assertEquals("Camera › Lens & zoom", searchHit("Camera", words, "ZOOM"))
        assertNull(searchHit("Camera", words, "telegram"))
        assertEquals("Camera", searchHit("Camera", words, " "))
    }
}
