package com.saeedkolivand.metastream.camera

import android.content.Context
import android.graphics.SurfaceTexture
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import android.view.Surface
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.utils.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.cos
import kotlin.math.sin

private const val VERTEX = """
attribute vec4 aPosition;
attribute vec2 aTextureCoord;
varying vec2 vTextureCoord;
void main() {
  gl_Position = aPosition;
  vTextureCoord = aTextureCoord;
}"""

// One pass: the previous frame, with the camera blended in through a rounded-box distance mask (circle = radius w/2).
private const val FRAGMENT = """
#extension GL_OES_EGL_image_external : require
precision mediump float;
uniform sampler2D uSampler;
uniform samplerExternalOES uCam;
uniform vec4 uRect;
uniform vec2 uSizePx;
uniform float uRadiusPx;
uniform vec2 uScale;
uniform mat2 uRot;
uniform mat4 uCamST;
uniform float uShow;
varying vec2 vTextureCoord;
void main() {
  vec4 base = texture2D(uSampler, vTextureCoord);
  vec2 q = (vTextureCoord - uRect.xy) / uRect.zw;
  if (uShow < 0.5 || q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) {
    gl_FragColor = base;
    return;
  }
  vec2 d = abs((q - 0.5) * uSizePx) - uSizePx * 0.5 + uRadiusPx;
  float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - uRadiusPx;
  float a = clamp(0.5 - dist, 0.0, 1.0);
  vec2 u = (q - 0.5) * uScale + 0.5;
  u.x = 1.0 - u.x;
  vec2 s = uRot * (u - 0.5) + 0.5;
  vec4 cam = texture2D(uCam, (uCamST * vec4(s, 0.0, 1.0)).xy);
  gl_FragColor = vec4(mix(base.rgb, cam.rgb, a), base.a);
}"""

private val QUAD = floatArrayOf(-1f, -1f, 0f, 0f, 0f, 1f, -1f, 0f, 1f, 0f, -1f, 1f, 0f, 0f, 1f, 1f, 1f, 0f, 1f, 1f)

/**
 * Draws the second camera over the stream in a masked window. RootEncoder's SurfaceFilterRender can't mask or rotate,
 * so this owns its SurfaceTexture: [onSurface] hands it out (main thread) once GL is up, [onGone] fires when GL drops it.
 * Window and camera geometry are set from any thread; the GL thread reads them each frame.
 */
class FaceCamFilter(private val onSurface: (FaceCamFilter, SurfaceTexture) -> Unit, private val onGone: (FaceCamFilter) -> Unit) :
    BaseFilterRender() {
    private val vertices = ByteBuffer.allocateDirect(QUAD.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        .apply { put(QUAD).position(0) }
    private var program = -1
    private val tex = IntArray(1)
    private var st: SurfaceTexture? = null
    private var surface: Surface? = null
    private val camMatrix = FloatArray(16).also { Matrix.setIdentityM(it, 0) }

    @Volatile private var rect = FloatArray(4)

    @Volatile private var sizeAndRadius = FloatArray(3)

    @Volatile private var scale = floatArrayOf(1f, 1f)

    @Volatile private var rot = floatArrayOf(1f, 0f, 0f, 1f)

    @Volatile var show = false

    @Volatile private var hasFrame = false

    /** The camera feeding this filter changed or stopped: hide the window until a fresh frame arrives. */
    fun clearFrame() {
        hasFrame = false
    }

    /** [r] in output pixels, top-left origin, as faceRect returns it. */
    fun setWindow(r: FaceRect, radius: Float, outW: Int, outH: Int) {
        rect = floatArrayOf(r.x / outW, 1f - (r.y + r.h) / outH, r.w / outW, r.h / outH)
        sizeAndRadius = floatArrayOf(r.w, r.h, radius)
        updateScale(r)
    }

    private var window = FaceRect(0f, 0f, 1f, 1f)
    private var uprightAspect = 1f

    /** [rotation]: degrees clockwise the sensor image needs to be upright; [w]x[h] is the camera buffer. */
    fun setCamera(w: Int, h: Int, rotation: Int) {
        val quarter = rotation / 90 % 2 == 1
        uprightAspect = if (quarter) h.toFloat() / w else w.toFloat() / h
        // The sensor image is the upright one rotated counter-clockwise by `rotation`.
        val t = Math.toRadians(rotation.toDouble())
        val c = cos(t).toFloat()
        val s = sin(t).toFloat()
        rot = floatArrayOf(c, s, -s, c)
        updateScale(window)
    }

    // Crop-to-fill: show the largest centred part of the camera image with the window's aspect.
    private fun updateScale(r: FaceRect) {
        window = r
        val a = r.w / r.h
        scale = if (uprightAspect > a) floatArrayOf(a / uprightAspect, 1f) else floatArrayOf(1f, uprightAspect / a)
    }

    override fun initGlFilter(context: Context) {
        program = GlUtil.createProgram(VERTEX, FRAGMENT)
        GlUtil.createExternalTextures(tex.size, tex, 0)
        val t = SurfaceTexture(tex[0])
        t.setOnFrameAvailableListener { hasFrame = true }
        st = t
        surface = Surface(t)
        onSurface(this, t)
    }

    override fun drawFilter() {
        st?.let {
            it.updateTexImage()
            it.getTransformMatrix(camMatrix)
        }
        GLES20.glUseProgram(program)
        vertices.position(0)
        val pos = GLES20.glGetAttribLocation(program, "aPosition")
        val uv = GLES20.glGetAttribLocation(program, "aTextureCoord")
        GLES20.glVertexAttribPointer(pos, 3, GLES20.GL_FLOAT, false, 20, vertices)
        GLES20.glEnableVertexAttribArray(pos)
        vertices.position(3)
        GLES20.glVertexAttribPointer(uv, 2, GLES20.GL_FLOAT, false, 20, vertices)
        GLES20.glEnableVertexAttribArray(uv)
        val r = rect
        val sr = sizeAndRadius
        GLES20.glUniform4f(loc("uRect"), r[0], r[1], r[2], r[3])
        GLES20.glUniform2f(loc("uSizePx"), sr[0], sr[1])
        GLES20.glUniform1f(loc("uRadiusPx"), sr[2])
        GLES20.glUniform2f(loc("uScale"), scale[0], scale[1])
        GLES20.glUniformMatrix2fv(loc("uRot"), 1, false, rot, 0)
        GLES20.glUniformMatrix4fv(loc("uCamST"), 1, false, camMatrix, 0)
        GLES20.glUniform1f(loc("uShow"), if (show && hasFrame) 1f else 0f)
        GLES20.glUniform1i(loc("uSampler"), 0)
        GLES20.glUniform1i(loc("uCam"), 1)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, previousTexId)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex[0])
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
    }

    private fun loc(name: String) = GLES20.glGetUniformLocation(program, name)

    override fun disableResources() {
        GlUtil.disableResources(GLES20.glGetAttribLocation(program, "aTextureCoord"), GLES20.glGetAttribLocation(program, "aPosition"))
    }

    override fun release() {
        surface?.release()
        st?.release()
        surface = null
        st = null
        GLES20.glDeleteProgram(program)
        GLES20.glDeleteTextures(1, tex, 0)
        onGone(this)
    }
}
