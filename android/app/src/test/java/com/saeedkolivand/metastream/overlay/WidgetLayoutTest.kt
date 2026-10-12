package com.saeedkolivand.metastream.overlay

import com.saeedkolivand.metastream.chat.Kind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetLayoutTest {
    private fun assertBox(a: Box, b: Box) {
        assertEquals(a.x, b.x, 0.01f)
        assertEquals(a.y, b.y, 0.01f)
        assertEquals(a.w, b.w, 0.01f)
        assertEquals(a.h, b.h, 0.01f)
    }

    private fun roundTrip(outW: Float, outH: Float) {
        for (anchor in 0..8) {
            // Any box survives the round trip exactly, even one big enough to be re-anchored by its centre.
            val big = widgetBox(WidgetLayout.inset(anchor, 1.5f), 600f, 500f, outW, outH)
            assertBox(big, widgetBox(widgetLayoutFor(big, 600f, 500f, outW, outH, 1.5f), 600f, 500f, outW, outH))
            // A small widget's centre stays in its own third, so it keeps its anchor.
            val small = widgetBox(WidgetLayout.inset(anchor), 100f, 50f, outW, outH)
            assertEquals("anchor $anchor", anchor, widgetLayoutFor(small, 100f, 50f, outW, outH, 1f).anchor)
        }
    }

    @Test fun roundTripLandscape() = roundTrip(1920f, 1080f)

    @Test fun roundTripPortrait() = roundTrip(1080f, 1920f)

    @Test fun bottomLeftInsetSitsInsideTheCorner() {
        val b = widgetBox(WidgetLayout.inset(6), 600f, 500f, 1920f, 1080f)
        assertBox(Box(48f, 1080f - 500f - 43.2f, 600f, 500f), b)
    }

    @Test fun centreAnchorCentresTheBox() {
        val b = widgetBox(WidgetLayout(4), 200f, 100f, 1920f, 1080f)
        assertBox(Box(860f, 490f, 200f, 100f), b)
    }

    @Test fun scaleFollowsTheShortSide() {
        val b = widgetBox(WidgetLayout(0, scale = 2f), 100f, 50f, 1080f, 1920f)
        assertBox(Box(0f, 0f, 200f, 100f), b)
    }

    @Test fun oldJsonWithoutLayoutOrCameraParses() {
        val json = """{"w":1920,"h":1080,"skipped":{},"scenes":[{"name":"A","layers":[{"t":"Text","n":"t","v":true,
            "pos":[1,2,1,1,0,0,0],"ints":[5,0,0,0,0,0,0],"d":{"text":"hi"},"f":[]}]}]}"""
        val scene = Pack.fromJson(json).scenes.single()
        assertNull(scene.camera)
        assertNull(scene.layers.single().layout)
    }

    @Test fun layoutAndCameraSurviveJson() {
        val layer = widgetLayer(LayerType.Chat, "chat", WidgetLayout(7, 0.1f, -0.2f, 1.25f), ChatStyle().toData())
        val pack = Pack(1920, 1080, listOf(Scene("S", listOf(layer), "front")), emptyMap())
        val back = Pack.fromJson(pack.toJson()).scenes.single()
        assertEquals("front", back.camera)
        assertEquals(WidgetLayout(7, 0.1f, -0.2f, 1.25f), back.layers.single().layout)
        assertEquals(layer.data, back.layers.single().data)
    }

    @Test fun stylesRoundTripAndDefaultFromEmpty() {
        assertEquals(ChatStyle(), ChatStyle.from(emptyMap()))
        assertEquals(AlertStyle(), AlertStyle.from(emptyMap()))
        assertEquals(EventListStyle(), EventListStyle.from(emptyMap()))
        assertEquals(QrStyle(), QrStyle.from(emptyMap()))
        assertEquals(TextStyle(), TextStyle.from(emptyMap()))

        val chat = ChatStyle(width = 321f, maxMessages = 3, backgroundColor = 0x12345678, highlight = "gg", bold = false)
        assertEquals(chat, ChatStyle.from(chat.toData()))
        assertEquals(ChatStyle(), ChatStyle.from(ChatStyle().toData()))
        val alert = AlertStyle(raid = false, holdSeconds = 9, accentColor = 0xFF010203.toInt())
        assertEquals(alert, AlertStyle.from(alert.toData()))
        val events = EventListStyle(tip = false, maxEvents = 2, backgroundColor = 0x73000000)
        assertEquals(events, EventListStyle.from(events.toData()))
        val qr = QrStyle(text = "x", caption = "scan", foreground = 0xFFFF0000.toInt())
        assertEquals(qr, QrStyle.from(qr.toData()))
        val text = TextStyle(text = "{time}", size = 10f, background = true, color = 0x80FFFFFF.toInt())
        assertEquals(text, TextStyle.from(text.toData()))
    }

    @Test fun colorsAreStoredAsUnsignedDecimal() {
        assertEquals("3641708564", ChatStyle(backgroundColor = 0xD9101014.toInt()).toData()["backgroundColor"])
        assertEquals(0xD9101014.toInt(), ChatStyle.from(mapOf("backgroundColor" to "3641708564")).backgroundColor)
    }

    @Test fun naturalSizesAndKinds() {
        assertEquals(600f to 500f, ChatStyle().natural)
        assertEquals(400f to 400f, QrStyle().natural)
        assertEquals(400f to 470f, QrStyle(caption = "c").natural)
        assertFalse(AlertStyle().shows(Kind.Message))
        assertTrue(AlertStyle().shows(Kind.Tip))
        assertFalse(EventListStyle(follow = false).shows(Kind.Follow))
    }
}
