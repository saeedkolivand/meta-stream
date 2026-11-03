package com.saeedkolivand.metastream.streaming

import android.content.Context
import android.opengl.GLES20
import android.opengl.Matrix
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.utils.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder

private const val STRIDE = 20

const val LOOK_VERTEX = """
uniform mat4 uMVPMatrix;
uniform mat4 uSTMatrix;
attribute vec4 aPosition;
attribute vec4 aTextureCoord;
varying vec2 vTextureCoord;
void main() {
  gl_Position = uMVPMatrix * aPosition;
  vTextureCoord = (uSTMatrix * aTextureCoord).xy;
}"""

/**
 * iOS LookEffect on the GPU: CIColorControls (saturation, brightness, contrast), a warmth cast and an optional 3D LUT.
 * GLES2 has no 3D textures, so the LUT is an atlas N*N wide and N tall (one N x N slice per blue level), two slices
 * sampled and mixed. ponytail: warmth scales the channels toward a 4500 K / 8500 K white instead of CITemperatureAndTint's
 * chromatic adaptation; the LUT is 8-bit, so very steep grades can band.
 */
const val LOOK_FRAGMENT = """
precision highp float;
varying vec2 vTextureCoord;
uniform sampler2D uSampler;
uniform sampler2D uLut;
uniform vec4 uAdj;
uniform float uLutSize;
void main() {
  vec4 c = texture2D(uSampler, vTextureCoord);
  vec3 rgb = mix(vec3(dot(c.rgb, vec3(0.2125, 0.7154, 0.0721))), c.rgb, uAdj.z);
  rgb = (rgb + uAdj.x - 0.5) * uAdj.y + 0.5;
  float w = uAdj.w;
  rgb *= w >= 0.0 ? mix(vec3(1.0), vec3(1.0, 0.9, 0.76), w) : mix(vec3(1.0), vec3(0.89, 0.93, 1.0), -w);
  rgb = clamp(rgb, 0.0, 1.0);
  if (uLutSize > 0.5) {
    float n = uLutSize;
    float bz = rgb.b * (n - 1.0);
    float b0 = floor(bz);
    float b1 = min(b0 + 1.0, n - 1.0);
    vec2 uv = vec2((rgb.r * (n - 1.0) + 0.5) / (n * n), (rgb.g * (n - 1.0) + 0.5) / n);
    rgb = mix(texture2D(uLut, uv + vec2(b0 / n, 0.0)).rgb, texture2D(uLut, uv + vec2(b1 / n, 0.0)).rgb, bz - b0);
  }
  gl_FragColor = vec4(rgb, c.a);
}"""

/** Grades every camera frame ahead of the overlays. [set] is thread-safe; a new LUT is uploaded on the GL thread. */
class LookFilter : BaseFilterRender() {
    @Volatile private var look = Look()

    @Volatile private var cube: Cube? = null

    @Volatile private var cubeDirty = false

    private var program = -1
    private val loc = IntArray(8)
    private val lutTex = IntArray(1)
    private var lutSize = 0

    init {
        val v = floatArrayOf(-1f, -1f, 0f, 0f, 0f, 1f, -1f, 0f, 1f, 0f, -1f, 1f, 0f, 0f, 1f, 1f, 1f, 0f, 1f, 1f)
        squareVertex = ByteBuffer.allocateDirect(v.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().also {
            it.put(v)
            it.position(0)
        }
    }

    fun set(next: Look, lut: Cube?) {
        look = next
        if (lut !== cube) {
            cube = lut
            cubeDirty = true
        }
    }

    override fun initGlFilter(context: Context) {
        program = GlUtil.createProgram(LOOK_VERTEX, LOOK_FRAGMENT)
        loc[0] = GLES20.glGetAttribLocation(program, "aPosition")
        loc[1] = GLES20.glGetAttribLocation(program, "aTextureCoord")
        listOf("uMVPMatrix", "uSTMatrix", "uSampler", "uLut", "uAdj", "uLutSize").forEachIndexed { i, u ->
            loc[2 + i] = GLES20.glGetUniformLocation(program, u)
        }
        GLES20.glGenTextures(1, lutTex, 0)
        cubeDirty = true
        Matrix.setIdentityM(MVPMatrix, 0)
        Matrix.setIdentityM(STMatrix, 0)
    }

    /** The cube as an RGBA8 atlas: pixel (r + b*N, g). */
    private fun uploadLut() {
        cubeDirty = false
        val c = cube
        lutSize = c?.size ?: 0
        if (c == null) return
        val n = c.size
        val bytes = ByteBuffer.allocateDirect(n * n * n * 4).order(ByteOrder.nativeOrder())
        for (g in 0 until n) {
            for (b in 0 until n) {
                for (r in 0 until n) {
                    val i = (r + g * n + b * n * n) * 3
                    for (k in 0..2) bytes.put((c.rgb[i + k].coerceIn(0f, 1f) * 255 + 0.5f).toInt().toByte())
                    bytes.put(0xFF.toByte())
                }
            }
        }
        bytes.position(0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, lutTex[0])
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, n * n, n, 0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, bytes)
    }

    override fun drawFilter() {
        if (cubeDirty) uploadLut()
        val l = look
        GLES20.glUseProgram(program)
        squareVertex.position(0)
        GLES20.glVertexAttribPointer(loc[0], 3, GLES20.GL_FLOAT, false, STRIDE, squareVertex)
        GLES20.glEnableVertexAttribArray(loc[0])
        squareVertex.position(3)
        GLES20.glVertexAttribPointer(loc[1], 2, GLES20.GL_FLOAT, false, STRIDE, squareVertex)
        GLES20.glEnableVertexAttribArray(loc[1])
        GLES20.glUniformMatrix4fv(loc[2], 1, false, MVPMatrix, 0)
        GLES20.glUniformMatrix4fv(loc[3], 1, false, STMatrix, 0)
        GLES20.glUniform4f(loc[6], l.brightness, l.contrast, l.saturation, l.warmth)
        GLES20.glUniform1f(loc[7], lutSize.toFloat())
        GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, lutTex[0])
        GLES20.glUniform1i(loc[5], 1)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, previousTexId)
        GLES20.glUniform1i(loc[4], 0)
    }

    override fun disableResources() {
        GLES20.glDisableVertexAttribArray(loc[0])
        GLES20.glDisableVertexAttribArray(loc[1])
    }

    override fun release() {
        GLES20.glDeleteProgram(program)
        GLES20.glDeleteTextures(1, lutTex, 0)
    }
}
