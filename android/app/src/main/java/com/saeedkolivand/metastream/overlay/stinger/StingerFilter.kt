package com.saeedkolivand.metastream.overlay

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.utils.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.ceil
import kotlin.math.hypot
import kotlin.math.min

private const val STRIDE = 20
private val UNIFORMS = arrayOf(
    "uMVPMatrix", "uSTMatrix", "uSampler", "uName", "uStroke", "uSize", "uP", "uCol", "uNameRect", "uNameA", "uOn"
)

/**
 * One built-in stinger over the whole frame, drawn by its fragment shader (StingerGlsl) on this filter's one pass. Per frame
 * the CPU works out ~20 numbers from the board's keyframes; the name and the route's line are rasterised once, before.
 * Time starts at the first frame it draws, so a busy GL thread can't skip its opening.
 */
internal class StingerFilter(
    private val kind: StingerKind,
    private val style: StingerStyle,
    private val name: Bitmap?,
    private val stroke: Bitmap?
) : BaseFilterRender() {
    private var program = -1
    private val loc = IntArray(UNIFORMS.size)
    private var aPosition = -1
    private var aTexCoord = -1
    private val textures = IntArray(2)
    private val frame = StingerFrame()
    private val colors = FloatArray(15)
    private var epoch = 0L

    init {
        val v = floatArrayOf(-1f, -1f, 0f, 0f, 0f, 1f, -1f, 0f, 1f, 0f, -1f, 1f, 0f, 0f, 1f, 1f, 1f, 0f, 1f, 1f)
        squareVertex = ByteBuffer.allocateDirect(v.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().also {
            it.put(v)
            it.position(0)
        }
        kind.colors(style).forEachIndexed { i, c ->
            colors[3 * i] = Color.red(c) / 255f
            colors[3 * i + 1] = Color.green(c) / 255f
            colors[3 * i + 2] = Color.blue(c) / 255f
        }
    }

    override fun initGlFilter(context: Context) {
        program = GlUtil.createProgram(FRAME_VERTEX, kind.fragmentShader())
        aPosition = GLES20.glGetAttribLocation(program, "aPosition")
        aTexCoord = GLES20.glGetAttribLocation(program, "aTextureCoord")
        UNIFORMS.forEachIndexed { i, u -> loc[i] = GLES20.glGetUniformLocation(program, u) }
        GLES20.glGenTextures(2, textures, 0)
        upload(textures[0], name)
        upload(textures[1], stroke)
        Matrix.setIdentityM(MVPMatrix, 0)
        Matrix.setIdentityM(STMatrix, 0)
    }

    private fun upload(id: Int, bmp: Bitmap?) {
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp ?: Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888), 0)
    }

    override fun drawFilter() {
        val w = getWidth().toFloat()
        val h = getHeight().toFloat()
        val now = System.nanoTime()
        if (epoch == 0L) epoch = now
        kind.frame(kind.q((now - epoch) / 1e9, style), style, w, h, frame)
        GLES20.glUseProgram(program)
        squareVertex.position(0)
        GLES20.glVertexAttribPointer(aPosition, 3, GLES20.GL_FLOAT, false, STRIDE, squareVertex)
        GLES20.glEnableVertexAttribArray(aPosition)
        squareVertex.position(3)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, STRIDE, squareVertex)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glUniformMatrix4fv(loc[0], 1, false, MVPMatrix, 0)
        GLES20.glUniformMatrix4fv(loc[1], 1, false, STMatrix, 0)
        GLES20.glUniform2f(loc[5], w, h)
        GLES20.glUniform1f(loc[10], if (frame.on) 1f else 0f) // off: the frame goes through unchanged
        GLES20.glUniform1fv(loc[6], STINGER_PARAMS, frame.p, 0)
        GLES20.glUniform3fv(loc[7], 5, colors, 0)
        val n = name
        if (n != null && frame.on && frame.nameAlpha > 0f) {
            val nw = n.width * frame.nameScale
            val nh = n.height * frame.nameScale
            GLES20.glUniform4f(loc[8], frame.nameX - nw / 2, frame.nameY - nh / 2, nw, nh)
            GLES20.glUniform1f(loc[9], frame.nameAlpha)
        } else {
            GLES20.glUniform1f(loc[9], 0f)
        }
        bind(0, loc[2], previousTexId)
        bind(1, loc[3], textures[0])
        bind(2, loc[4], textures[1])
    }

    private fun bind(unit: Int, uniform: Int, id: Int) {
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0 + unit)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
        GLES20.glUniform1i(uniform, unit)
    }

    override fun disableResources() {
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
    }

    override fun release() {
        GLES20.glDeleteProgram(program)
        GLES20.glDeleteTextures(2, textures, 0)
    }

    companion object {
        /** Rasterises what the stinger needs once (name text, the route's line) for a [w] x [h] output. Off the GL thread. */
        fun build(kind: StingerKind, style: StingerStyle, w: Int, h: Int): StingerFilter {
            val u = min(w, h) / 1080f
            val name = if (style.showName && style.name.isNotEmpty()) nameBitmap(kind.nameLook(style), style.name, u) else null
            val stroke = if (kind == StingerKind.Route) routeStroke(w, h, u) else null
            return StingerFilter(kind, style, name, stroke)
        }

        private fun nameBitmap(look: NameLook, text: String, u: Float): Bitmap {
            val paint = widgetPaint("", if (look.bold) 600 else 400, look.size * u, look.color).apply { letterSpacing = look.tracking }
            val fm = paint.fontMetrics
            val bmp = newBitmap(ceil(paint.measureText(text)) + 2, ceil(fm.bottom - fm.top))
            Canvas(bmp).drawText(text, 1f, -fm.top, paint)
            return bmp
        }

        /**
         * The route as a canvas-sized line with its progress along the path (0...1) in red, so the shader can draw any
         * prefix of it: "M -40 1000 C 360 1000 420 640 760 720 C 1000 776 1080 610 960 540", 8 board px wide.
         */
        private fun routeStroke(w: Int, h: Int, u: Float): Bitmap {
            val segs = arrayOf(
                floatArrayOf(-40f, 1000f, 360f, 1000f, 420f, 640f, 760f, 720f),
                floatArrayOf(760f, 720f, 1000f, 776f, 1080f, 610f, 960f, 540f)
            )
            val pts = ArrayList<FloatArray>()
            for (s in segs) {
                for (i in 0..100) {
                    val t = i / 100f
                    val m = 1 - t
                    val x = m * m * m * s[0] + 3 * m * m * t * s[2] + 3 * m * t * t * s[4] + t * t * t * s[6]
                    val y = m * m * m * s[1] + 3 * m * m * t * s[3] + 3 * m * t * t * s[5] + t * t * t * s[7]
                    pts += floatArrayOf(w / 2f + (x - 960) * u, h / 2f + (y - 540) * u)
                }
            }
            val cum = FloatArray(pts.size)
            for (i in 1 until pts.size) cum[i] = cum[i - 1] + hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
            val total = cum.last().coerceAtLeast(0.001f)
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = 8 * u
                strokeCap = Paint.Cap.ROUND
            }
            for (i in 1 until pts.size) {
                paint.color = Color.argb(255, (cum[i] / total * 255).toInt(), 0, 0)
                c.drawLine(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], paint)
            }
            return bmp
        }
    }
}
