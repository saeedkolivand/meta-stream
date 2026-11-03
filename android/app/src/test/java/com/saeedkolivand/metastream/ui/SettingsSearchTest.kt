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

class SceneTemplateTest {
    @Test
    fun monoSetHasTheThreeRolesAndChannelQr() {
        val scenes = com.saeedkolivand.metastream.overlay.SceneTemplate.Mono.scenes(
            "Saeed",
            com.saeedkolivand.metastream.overlay.ColorTheme.Paper
        )
        assertEquals(listOf("starting", "brb", "ending"), scenes.map { it.role })
        assertEquals("https://kick.com/saeed", scenes[2].layers.last().data["text"])
        assertNull(
            com.saeedkolivand.metastream.overlay.SceneTemplate.Mono.scenes(
                "",
                com.saeedkolivand.metastream.overlay.ColorTheme.Kick
            ).last().layers.firstOrNull {
                it.name ==
                    "QR code"
            }
        )
    }
}
