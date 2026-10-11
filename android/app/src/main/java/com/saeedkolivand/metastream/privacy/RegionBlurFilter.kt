package com.saeedkolivand.metastream.privacy

import android.content.Context
import android.graphics.Bitmap
import android.opengl.GLES20
import android.os.SystemClock
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.utils.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.roundToInt

/** What the GL thread asks of the pipeline: boxes to hide now, and when to hand a frame to detection. */
interface BlurFeed {
    /** Packed (left, bottom, right, top) in GL texture space, or null = hide the whole frame (fail closed). */
    fun rects(now: Long): FloatArray?

    fun wantFrame(now: Long): Boolean

    fun onFrame(frame: Bitmap)
}

private const val MAX_RECTS = BoxTracker.MAX_BOXES

private const val VERTEX = """
uniform mat4 uMVPMatrix;
uniform mat4 uSTMatrix;
attribute vec4 aPosition;
attribute vec4 aTextureCoord;
varying vec2 vTextureCoord;
void main() {
  gl_Position = uMVPMatrix * aPosition;
  vTextureCoord = (uSTMatrix * aTextureCoord).xy;
}"""

// Pixelates (like iOS CIPixellate) inside the rects, or everywhere when uFull is set; uFlip is for the detection copy only.
private const val FRAGMENT = """
precision mediump float;
varying vec2 vTextureCoord;
uniform sampler2D uSampler;
uniform vec4 uRects[$MAX_RECTS];
uniform int uCount;
uniform float uFull;
uniform float uFlip;
uniform vec2 uBlock;
void main() {
  vec2 uv = vTextureCoord;
  if (uFlip > 0.5) uv.y = 1.0 - uv.y;
  bool hit = uFull > 0.5;
  for (int i = 0; i < $MAX_RECTS; i++) {
    if (i < uCount) {
      vec4 r = uRects[i];
      if (uv.x >= r.x && uv.x <= r.z && uv.y >= r.y && uv.y <= r.w) hit = true;
    }
  }
  vec2 p = hit ? (floor(uv / uBlock) + 0.5) * uBlock : uv;
  gl_FragColor = texture2D(uSampler, p);
}"""

private const val BLOCK_PX = 24f // iOS pixellateScale, tuned for 720 px wide
private const val DETECT_MAX_DIM = 640

/**
 * First filter in the chain, so it sees the raw camera frame and everything after it (overlays, alerts) stays sharp.
 * Besides blurring it hands a downscaled copy of that raw frame to detection, which is why detection and blur always agree
 * on rotation, mirror and crop: both live in this filter's texture space.
 */
class RegionBlurFilter(private val feed: BlurFeed) : BaseFilterRender() {
    private var program = -1
    private var aPos = -1
    private var aTex = -1
    private var uMvp = -1
    private var uSt = -1
    private var uSampler = -1
    private var uRects = -1
    private var uCount = -1
    private var uFull = -1
    private var uFlip = -1
    private var uBlock = -1
    private val fbo = IntArray(1)
    private val tex = IntArray(1)
    private var capW = 0
    private var capH = 0
    private var pixels: ByteBuffer? = null

    init {
        val v = floatArrayOf(-1f, -1f, 0f, 0f, 0f, 1f, -1f, 0f, 1f, 0f, -1f, 1f, 0f, 0f, 1f, 1f, 1f, 0f, 1f, 1f)
        squareVertex = ByteBuffer.allocateDirect(v.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().also {
            it.put(v)
            it.position(0)
        }
        android.opengl.Matrix.setIdentityM(MVPMatrix, 0)
        android.opengl.Matrix.setIdentityM(STMatrix, 0)
    }

    override fun initGlFilter(context: Context) {
        program = GlUtil.createProgram(VERTEX, FRAGMENT)
        aPos = GLES20.glGetAttribLocation(program, "aPosition")
        aTex = GLES20.glGetAttribLocation(program, "aTextureCoord")
        uMvp = GLES20.glGetUniformLocation(program, "uMVPMatrix")
        uSt = GLES20.glGetUniformLocation(program, "uSTMatrix")
        uSampler = GLES20.glGetUniformLocation(program, "uSampler")
        uRects = GLES20.glGetUniformLocation(program, "uRects")
        uCount = GLES20.glGetUniformLocation(program, "uCount")
        uFull = GLES20.glGetUniformLocation(program, "uFull")
        uFlip = GLES20.glGetUniformLocation(program, "uFlip")
        uBlock = GLES20.glGetUniformLocation(program, "uBlock")
    }

    override fun drawFilter() {
        val now = SystemClock.elapsedRealtime()
        if (feed.wantFrame(now)) runCatching { capture() }
        bind(rects = feed.rects(now), flip = false)
    }

    private fun bind(rects: FloatArray?, flip: Boolean) {
        GLES20.glUseProgram(program)
        squareVertex.position(0)
        GLES20.glVertexAttribPointer(aPos, 3, GLES20.GL_FLOAT, false, STRIDE, squareVertex)
        GLES20.glEnableVertexAttribArray(aPos)
        squareVertex.position(3)
        GLES20.glVertexAttribPointer(aTex, 2, GLES20.GL_FLOAT, false, STRIDE, squareVertex)
        GLES20.glEnableVertexAttribArray(aTex)
        GLES20.glUniformMatrix4fv(uMvp, 1, false, MVPMatrix, 0)
        GLES20.glUniformMatrix4fv(uSt, 1, false, STMatrix, 0)
        val n = (rects?.size ?: 0) / 4
        if (n > 0) GLES20.glUniform4fv(uRects, n, rects, 0)
        GLES20.glUniform1i(uCount, n)
        GLES20.glUniform1f(uFull, if (rects == null) 1f else 0f)
        GLES20.glUniform1f(uFlip, if (flip) 1f else 0f)
        val px = BLOCK_PX * minOf(width, height) / 720f
        GLES20.glUniform2f(uBlock, max(px, 1f) / width, max(px, 1f) / height)
        GLES20.glUniform1i(uSampler, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, previousTexId)
    }

    /** Draws the untouched input, y-flipped so row 0 is the top, into a small FBO and reads it back as a bitmap. */
    private fun capture() {
        val prev = IntArray(1)
        GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, prev, 0)
        ensureCaptureTarget()
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo[0])
        GLES20.glViewport(0, 0, capW, capH)
        bind(rects = FloatArray(0), flip = true)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        val buf = requireNotNull(pixels).also { it.rewind() }
        GLES20.glReadPixels(0, 0, capW, capH, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buf)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, prev[0])
        GLES20.glViewport(0, 0, width, height)
        buf.rewind()
        feed.onFrame(Bitmap.createBitmap(capW, capH, Bitmap.Config.ARGB_8888).also { it.copyPixelsFromBuffer(buf) })
    }

    private fun ensureCaptureTarget() {
        if (tex[0] != 0) return
        val s = DETECT_MAX_DIM.toFloat() / max(width, height)
        capW = (width * s).roundToInt().coerceAtLeast(1)
        capH = (height * s).roundToInt().coerceAtLeast(1)
        pixels = ByteBuffer.allocateDirect(capW * capH * 4).order(ByteOrder.nativeOrder())
        GLES20.glGenTextures(1, tex, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex[0])
        GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, capW, capH, 0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glGenFramebuffers(1, fbo, 0)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo[0])
        GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0, GLES20.GL_TEXTURE_2D, tex[0], 0)
    }

    override fun disableResources() {
        GlUtil.disableResources(aTex, aPos)
    }

    override fun release() {
        GLES20.glDeleteProgram(program)
        if (tex[0] != 0) {
            GLES20.glDeleteTextures(1, tex, 0)
            GLES20.glDeleteFramebuffers(1, fbo, 0)
            tex[0] = 0
        }
    }

    private companion object {
        const val STRIDE = 20
    }
}
