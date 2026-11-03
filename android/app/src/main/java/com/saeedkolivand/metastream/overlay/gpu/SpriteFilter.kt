package com.saeedkolivand.metastream.overlay

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.utils.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.IdentityHashMap
import kotlin.math.cos
import kotlin.math.sin

private const val STRIDE = 20
private const val ITEM_FLOATS = 8 // aPosition, aUv, aLocal, aBox
private val ATTRS = arrayOf("aPosition", "aUv", "aLocal", "aBox")

// ponytail: an unused texture lives ~2 s (60 frames at 30 fps) before it's deleted, so emote frames and items that blink
// to alpha 0 aren't re-uploaded; per-scene bitmap lists would free them sooner.
private const val TEXTURE_GRACE_FRAMES = 60

/**
 * Draws a [GpuScene] over the frame: one copy pass, then a quad per item, all in this filter's one pass. Bitmaps are uploaded
 * once (on this GL thread) and kept by identity, so a chat row or an alert's text is rasterised once, not per frame.
 * Placement matches [placeIn]: the scene fills the layer's box, rotated clockwise (OBS) about the box centre.
 */
internal class SpriteFilter : BaseFilterRender() {
    @Volatile private var scene: GpuScene? = null

    @Volatile private var sceneAlpha = 1f

    private var box = Box(0f, 0f, 1f, 1f)
    private var cosR = 1f
    private var sinR = 0f
    private var drawBox = box
    private var drawCos = 1f
    private var drawSin = 0f
    private var itemCos = 1f
    private var itemSin = 0f

    private var frameProgram = -1
    private var itemProgram = -1
    private val frameLoc = IntArray(5)
    private val loc = HashMap<String, Int>()
    private val textures = IdentityHashMap<Bitmap, IntArray>() // [texture id, last frame used]
    private var frame = 0
    private lateinit var quad: FloatBuffer

    init {
        val v = floatArrayOf(-1f, -1f, 0f, 0f, 0f, 1f, -1f, 0f, 1f, 0f, -1f, 1f, 0f, 0f, 1f, 1f, 1f, 0f, 1f, 1f)
        squareVertex = ByteBuffer.allocateDirect(v.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().also {
            it.put(v)
            it.position(0)
        }
    }

    /** Thread-safe; null draws nothing. */
    fun show(next: GpuScene?) {
        scene = next
    }

    /** The scene-transition fade (FilterSink), multiplied into every item. */
    fun setAlpha(a: Float) {
        sceneAlpha = a
    }

    /** Called once before the filter joins the chain. [box] is in output px, [rotation] in OBS degrees (clockwise). */
    fun place(b: Box, rotation: Float = 0f): SpriteFilter {
        box = b
        val rad = Math.toRadians(rotation.toDouble())
        cosR = cos(rad).toFloat()
        sinR = sin(rad).toFloat()
        return this
    }

    override fun initGlFilter(context: Context) {
        frameProgram = GlUtil.createProgram(FRAME_VERTEX, FRAME_FRAGMENT)
        itemProgram = GlUtil.createProgram(ITEM_VERTEX, ITEM_FRAGMENT)
        frameLoc[0] = GLES20.glGetAttribLocation(frameProgram, "aPosition")
        frameLoc[1] = GLES20.glGetAttribLocation(frameProgram, "aTextureCoord")
        frameLoc[2] = GLES20.glGetUniformLocation(frameProgram, "uSampler")
        frameLoc[3] = GLES20.glGetUniformLocation(frameProgram, "uMVPMatrix")
        frameLoc[4] = GLES20.glGetUniformLocation(frameProgram, "uSTMatrix")
        for (a in ATTRS) loc[a] = GLES20.glGetAttribLocation(itemProgram, a)
        val uniforms = listOf("uTex", "uUseTex", "uColor", "uSizePx", "uRadius", "uClip", "uClipRadius", "uAlpha", "uBoxPx", "uTopFade")
        for (u in uniforms) loc[u] = GLES20.glGetUniformLocation(itemProgram, u)
        quad = ByteBuffer.allocateDirect(4 * ITEM_FLOATS * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        Matrix.setIdentityM(MVPMatrix, 0)
        Matrix.setIdentityM(STMatrix, 0)
    }

    // Same steps as BaseFilterRender.draw() (bind FBO, viewport, draw, unbind), but with two programs.
    override fun draw() {
        val w = getWidth()
        val h = getHeight()
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, getRenderHandler().getFboId()[0])
        GLES20.glViewport(0, 0, w, h)
        copyFrame()
        frame++
        val s = scene
        if (s != null && s.width > 0f && s.height > 0f) {
            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA) // bitmaps and colours are premultiplied
            drawItems(s, w, h)
            GLES20.glDisable(GLES20.GL_BLEND)
        }
        sweep()
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
    }

    private fun copyFrame() {
        GLES20.glUseProgram(frameProgram)
        squareVertex.position(0)
        GLES20.glVertexAttribPointer(frameLoc[0], 3, GLES20.GL_FLOAT, false, STRIDE, squareVertex)
        GLES20.glEnableVertexAttribArray(frameLoc[0])
        squareVertex.position(3)
        GLES20.glVertexAttribPointer(frameLoc[1], 2, GLES20.GL_FLOAT, false, STRIDE, squareVertex)
        GLES20.glEnableVertexAttribArray(frameLoc[1])
        GLES20.glUniformMatrix4fv(frameLoc[3], 1, false, MVPMatrix, 0)
        GLES20.glUniformMatrix4fv(frameLoc[4], 1, false, STMatrix, 0)
        GLES20.glUniform1i(frameLoc[2], 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, previousTexId)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(frameLoc[0])
        GLES20.glDisableVertexAttribArray(frameLoc[1])
    }

    private fun u(name: String) = loc.getValue(name)

    private fun drawItems(s: GpuScene, w: Int, h: Int) {
        val b = if (s.canvas) Box(0f, 0f, w.toFloat(), h.toFloat()) else box
        drawBox = b
        drawCos = if (s.canvas) 1f else cosR
        drawSin = if (s.canvas) 0f else sinR
        val sx = b.w / s.width
        val sy = b.h / s.height
        GLES20.glUseProgram(itemProgram)
        GLES20.glUniform1i(u("uTex"), 0)
        GLES20.glUniform2f(u("uBoxPx"), b.w, b.h)
        GLES20.glUniform1f(u("uTopFade"), s.topFade * b.h)
        val t = (System.nanoTime() - s.epochNanos) / 1e9f
        for (item in s.items(t)) {
            val r = item.rect
            item.image?.let(::texture) // touch even when invisible, so the grace period covers blinking items
            if (r.width() <= 0f || r.height() <= 0f || item.alpha <= 0f) continue
            val wPx = r.width() * sx
            val hPx = r.height() * sy
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, item.image?.let(::texture) ?: 0)
            GLES20.glUniform1f(u("uUseTex"), if (item.image == null) 0f else 1f)
            val c = item.color
            GLES20.glUniform4f(u("uColor"), Color.red(c) / 255f, Color.green(c) / 255f, Color.blue(c) / 255f, Color.alpha(c) / 255f)
            GLES20.glUniform2f(u("uSizePx"), wPx, hPx)
            GLES20.glUniform1f(u("uRadius"), item.radius * minOf(sx, sy))
            val k = item.clip
            if (k == null) {
                GLES20.glUniform4f(u("uClip"), 0f, 0f, 0f, 0f)
            } else {
                GLES20.glUniform4f(u("uClip"), (k.left - r.left) * sx, (k.top - r.top) * sy, k.width() * sx, k.height() * sy)
            }
            GLES20.glUniform1f(u("uClipRadius"), item.clipRadius * minOf(sx, sy))
            GLES20.glUniform1f(u("uAlpha"), item.alpha * sceneAlpha)
            if (item.rotation == 0f) {
                itemCos = 1f
                itemSin = 0f
            } else {
                val rad = Math.toRadians(item.rotation.toDouble())
                itemCos = cos(rad).toFloat()
                itemSin = sin(rad).toFloat()
            }
            vertices(r.left * sx, r.top * sy, wPx, hPx, w, h)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }
        for (a in ATTRS) GLES20.glDisableVertexAttribArray(u(a))
    }

    /** The item's corners, given in box px (top-left origin), rotated about the box centre and mapped to clip space. */
    private fun vertices(x: Float, y: Float, wPx: Float, hPx: Float, outW: Int, outH: Int) {
        quad.clear()
        corner(x, y, 0f, 0f, wPx, hPx, outW, outH)
        corner(x, y, 1f, 0f, wPx, hPx, outW, outH)
        corner(x, y, 0f, 1f, wPx, hPx, outW, outH)
        corner(x, y, 1f, 1f, wPx, hPx, outW, outH)
        var offset = 0
        for (a in ATTRS) {
            quad.position(offset)
            GLES20.glVertexAttribPointer(u(a), 2, GLES20.GL_FLOAT, false, ITEM_FLOATS * 4, quad)
            GLES20.glEnableVertexAttribArray(u(a))
            offset += 2
        }
    }

    /** Corner ([uu], [vv]) of the item at ([x], [y]) box px, size [wPx] x [hPx]. */
    private fun corner(x: Float, y: Float, uu: Float, vv: Float, wPx: Float, hPx: Float, outW: Int, outH: Int) {
        val b = drawBox
        val lx = uu * wPx
        val ly = vv * hPx
        // the item's own turn about its centre, then the widget's about the box centre
        val dx = lx - wPx / 2
        val dy = ly - hPx / 2
        val bx = x + wPx / 2 + dx * itemCos - dy * itemSin
        val by = y + hPx / 2 + dx * itemSin + dy * itemCos
        val ox = bx - b.w / 2
        val oy = by - b.h / 2
        // y grows down, so this standard rotation turns clockwise on screen, like OBS.
        val px = b.x + b.w / 2 + ox * drawCos - oy * drawSin
        val py = b.y + b.h / 2 + ox * drawSin + oy * drawCos
        quad.put(px / outW * 2f - 1f)
        quad.put(1f - py / outH * 2f)
        quad.put(uu)
        quad.put(vv)
        quad.put(lx)
        quad.put(ly)
        quad.put(bx)
        quad.put(by)
    }

    private fun texture(bmp: Bitmap): Int {
        textures[bmp]?.let {
            it[1] = frame
            return it[0]
        }
        val id = IntArray(1)
        GLES20.glGenTextures(1, id, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id[0])
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)
        textures[bmp] = intArrayOf(id[0], frame)
        return id[0]
    }

    private fun sweep() {
        val it = textures.values.iterator()
        while (it.hasNext()) {
            val e = it.next()
            if (frame - e[1] > TEXTURE_GRACE_FRAMES) {
                GLES20.glDeleteTextures(1, e, 0)
                it.remove()
            }
        }
    }

    override fun drawFilter() = Unit

    override fun disableResources() = Unit

    override fun release() {
        GLES20.glDeleteProgram(frameProgram)
        GLES20.glDeleteProgram(itemProgram)
        textures.values.forEach { GLES20.glDeleteTextures(1, it, 0) }
        textures.clear()
        scene = null
    }
}
