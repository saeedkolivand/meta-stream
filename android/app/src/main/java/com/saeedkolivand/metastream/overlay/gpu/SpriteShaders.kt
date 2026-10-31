package com.saeedkolivand.metastream.overlay

/** Copies the incoming frame unchanged; the items blend over it. */
internal const val FRAME_VERTEX = """
uniform mat4 uMVPMatrix;
uniform mat4 uSTMatrix;
attribute vec4 aPosition;
attribute vec4 aTextureCoord;
varying vec2 vTextureCoord;
void main() {
  gl_Position = uMVPMatrix * aPosition;
  vTextureCoord = (uSTMatrix * aTextureCoord).xy;
}"""

internal const val FRAME_FRAGMENT = """
precision mediump float;
varying vec2 vTextureCoord;
uniform sampler2D uSampler;
void main() {
  gl_FragColor = texture2D(uSampler, vTextureCoord);
}"""

/** aLocal = px inside the item, aBox = px inside the widget box; both before rotation, so masks rotate with the widget. */
internal const val ITEM_VERTEX = """
attribute vec2 aPosition;
attribute vec2 aUv;
attribute vec2 aLocal;
attribute vec2 aBox;
varying vec2 vUv;
varying vec2 vLocal;
varying vec2 vBox;
void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
  vUv = aUv;
  vLocal = aLocal;
  vBox = aBox;
}"""

/**
 * One item: a premultiplied texture (times uColor) or a solid colour, masked by an antialiased rounded rect (uRadius),
 * an optional rounded clip (uClip, item px), the widget box, and the box's top fade.
 */
internal const val ITEM_FRAGMENT = """
precision mediump float;
varying vec2 vUv;
varying vec2 vLocal;
varying vec2 vBox;
uniform sampler2D uTex;
uniform float uUseTex;
uniform vec4 uColor;
uniform vec2 uSizePx;
uniform float uRadius;
uniform vec4 uClip;
uniform float uClipRadius;
uniform float uAlpha;
uniform vec2 uBoxPx;
uniform float uTopFade;

float sdRound(vec2 p, vec2 half, float r) {
  vec2 d = abs(p) - half + vec2(r);
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void main() {
  vec2 half = uSizePx * 0.5;
  float a = clamp(0.5 - sdRound(vLocal - half, half, uRadius), 0.0, 1.0);
  if (uClip.z > 0.0) {
    vec2 ch = uClip.zw * 0.5;
    a *= clamp(0.5 - sdRound(vLocal - uClip.xy - ch, ch, uClipRadius), 0.0, 1.0);
  }
  a *= step(0.0, vBox.x) * step(vBox.x, uBoxPx.x) * step(0.0, vBox.y) * step(vBox.y, uBoxPx.y);
  if (uTopFade > 0.0) a *= clamp(vBox.y / uTopFade, 0.0, 1.0);
  a *= uAlpha;
  vec4 c = uUseTex > 0.5 ? texture2D(uTex, vUv) * uColor : vec4(uColor.rgb * uColor.a, uColor.a);
  gl_FragColor = c * a;
}"""
