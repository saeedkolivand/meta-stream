package com.saeedkolivand.metastream.overlay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ObsParserTest {
    // Synthetic collection with fake URLs: a scene with a browser source, a group holding an image and text, and PC-only sources.
    private val json = """
    {"sources":[
     {"id":"browser_source","name":"alerts","uuid":"u1","settings":{"url":"https://example.invalid/alerts","width":1920,"height":1080,"css":"body{color:red}"}},
     {"id":"browser_source","name":"local","uuid":"u2","settings":{"url":"file:///c:/x.html","is_local_file":true}},
     {"id":"image_source","name":"frame","uuid":"u3","settings":{"file":"E:/fake/Frames/frame.png"}},
     {"id":"text_gdiplus","name":"title","uuid":"u4","settings":{"text":"Hello","font":{"face":"Arial","size":48,"flags":1},"color":4278190335}},
     {"id":"dshow_input","name":"cam","uuid":"u5","settings":{}},
     {"id":"game_capture","name":"game","uuid":"u6","settings":{}},
     {"id":"wasapi_input_capture","name":"mic","uuid":"u7","settings":{}},
     {"id":"ffmpeg_source","name":"clip","uuid":"u8","settings":{"local_file":"E:/fake/clip.mp4","looping":true}},
     {"id":"group","name":"grp","uuid":"g1","settings":{"items":[
        {"name":"frame","source_uuid":"u3","pos":{"x":10,"y":20},"scale":{"x":2,"y":2},"visible":true},
        {"name":"title","source_uuid":"u4","pos":{"x":0,"y":0},"visible":false}]}},
     {"id":"scene","name":"Live","uuid":"s1","settings":{"items":[
        {"name":"cam","source_uuid":"u5"},
        {"name":"alerts","source_uuid":"u1","pos":{"x":0,"y":0},"bounds_type":2,"bounds":{"x":960,"y":540},"bounds_align":0},
        {"name":"grp","source_uuid":"g1","pos":{"x":100,"y":100},"scale":{"x":0.5,"y":0.5}},
        {"name":"clip","source_uuid":"u8","visible":true},
        {"name":"local","source_uuid":"u2"}]}},
     {"id":"scene","name":"BRB","uuid":"s2","settings":{"items":[{"name":"mic","source_uuid":"u7"}]}}
    ]}
    """

    private val pack = parseObs(json)

    @Test fun scenesAndLayerTypes() {
        assertEquals(listOf("Live", "BRB"), pack.scenes.map { it.name })
        assertEquals(
            listOf(LayerType.Browser, LayerType.Image, LayerType.Text, LayerType.Media),
            pack.scenes[0].layers.map { it.type }
        )
        assertTrue(pack.scenes[1].layers.isEmpty())
    }

    @Test fun groupTransformIsFlattened() {
        val image = pack.scenes[0].layers[1]
        assertEquals(100f + 0.5f * 10, image.x, 0.001f)
        assertEquals(100f + 0.5f * 20, image.y, 0.001f)
        assertEquals(1.0f, image.sx, 0.001f)
        assertTrue(image.visible)
        assertTrue(!pack.scenes[0].layers[2].visible) // hidden inside the group
    }

    @Test fun skippedSourcesAreCountedByCategory() {
        assertEquals(mapOf("cameras" to 1, "audio" to 1, "non-web browser pages" to 1), pack.skipped)
        assertTrue(pack.skippedText().startsWith("Skipped"))
    }

    @Test fun payloads() {
        val b = pack.scenes[0].layers[0]
        assertEquals("https://example.invalid/alerts", b.data["url"])
        assertEquals("body{color:red}", b.data["css"])
        assertEquals(960f, b.bw, 0.001f)
        val t = pack.scenes[0].layers[2]
        assertEquals("true", t.data["bold"])
        assertEquals(0xFFFF0000L, t.data["color"]?.toLong()?.and(0xFFFFFFFFL)) // OBS ABGR 0xFF0000FF is opaque red
        assertEquals("true", pack.scenes[0].layers[3].data["loop"])
    }

    @Test fun packSurvivesJson() {
        assertEquals(pack, Pack.fromJson(pack.toJson()))
        assertEquals(setOf("E:/fake/Frames/frame.png", "E:/fake/clip.mp4"), pack.files())
    }

    @Test fun garbageIsRejected() {
        assertTrue(runCatching { parseObs("not json") }.isFailure)
        assertTrue(parseObs("{}").scenes.isEmpty())
    }
}
