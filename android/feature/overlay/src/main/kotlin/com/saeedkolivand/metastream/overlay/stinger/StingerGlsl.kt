package com.saeedkolivand.metastream.overlay

/**
 * The stingers as fragment shaders: every pixel of the art is evaluated here, on the GPU, from a few numbers per frame
 * (StingerFrames). p is the pixel in canvas px with a top-left origin, like the iOS boards. The result is premultiplied and
 * goes over the frame. Blurs (the lens crescent, the liquid goo) are smooth edges, not real blurs.
 */
private const val PRELUDE = """
precision highp float;
varying vec2 vTextureCoord;
uniform sampler2D uSampler;
uniform sampler2D uName;
uniform sampler2D uStroke;
uniform vec2 uSize;
uniform float uP[20];
uniform vec3 uCol[5];
uniform vec4 uNameRect;
uniform float uNameA;
uniform float uOn;
#define RGB(r, g, b) (vec3(r, g, b) / 255.0)
float disc(vec2 p, vec2 c, float r) { return clamp(r - length(p - c) + 0.5, 0.0, 1.0); }
float soft(vec2 p, vec2 c, float r, float s) { return 1.0 - smoothstep(r - s, r + s, length(p - c)); }
float rect(vec2 p, vec4 r) {
  vec2 a = clamp(p - r.xy + 0.5, 0.0, 1.0) * clamp(r.xy + r.zw - p + 0.5, 0.0, 1.0);
  return a.x * a.y;
}
vec4 over(vec4 d, vec3 c, float a) { return vec4(c * a, a) + d * (1.0 - a); }
vec4 overP(vec4 d, vec4 s) { return s + d * (1.0 - s.a); }
vec2 rot(vec2 v, float deg) {
  float r = radians(deg);
  float c = cos(r);
  float s = sin(r);
  return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}
vec4 nameAt(vec2 p) {
  if (uNameA <= 0.0) return vec4(0.0);
  vec2 uv = (p - uNameRect.xy) / uNameRect.zw;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec4(0.0);
  return texture2D(uName, uv) * uNameA;
}
"""

private const val MAIN = """
void main() {
  vec4 frame = texture2D(uSampler, vTextureCoord);
  vec4 s = uOn > 0.5 ? stinger(vec2(vTextureCoord.x, 1.0 - vTextureCoord.y) * uSize) : vec4(0.0);
  gl_FragColor = s + frame * (1.0 - s.a);
}
"""

private const val LENS = """
vec4 stinger(vec2 p) {
  vec2 C = uSize * 0.5;
  float u = uP[19];
  float hole = uP[0];
  vec3 g1 = RGB(28.0, 28.0, 31.0);
  vec3 g2 = RGB(10.0, 10.0, 12.0);
  vec4 a = over(vec4(0.0), mix(g1, g2, p.y / uSize.y), 1.0 - disc(p, C, hole - 12.0 * u));
  if (uP[1] > 0.001) a = over(a, mix(g1, g2, clamp((p.y - C.y + 216.0 * u) / (432.0 * u), 0.0, 1.0)), uP[1] * disc(p, C, 216.0 * u));
  if (uP[2] > 0.001) {
    float gd = disc(p, C, 203.0 * u);
    vec4 g = over(vec4(0.0), mix(RGB(22.0, 24.0, 30.0), RGB(2.0, 2.0, 3.0), clamp(length(p - C) / (200.0 * u), 0.0, 1.0)), gd);
    g = over(g, vec3(1.0), 0.07 * (disc(p, C, 139.0 * u) - disc(p, C, 136.0 * u)));
    float cres = soft(p, C + vec2(-21.0, -21.0) * u, 182.0 * u, 6.0 * u) * (1.0 - soft(p, C + vec2(-1.0, 13.0) * u, 182.0 * u, 6.0 * u));
    g = over(g, vec3(1.0), 0.16 * cres * gd);
    a = overP(a, g * uP[2]);
  }
  if (uP[3] > 0.001) a = over(a, uCol[0], uP[3] * clamp(1.0 - length(p - C) / uP[4], 0.0, 1.0));
  if (uP[5] > 0.001) {
    float r = 42.0 * u * uP[6];
    float d = disc(p, C, r);
    vec4 t = over(vec4(0.0), mix(uCol[1], uCol[0], clamp((p.y - C.y + r) / (2.0 * r), 0.0, 1.0)), d);
    t = over(t, vec3(1.0), 0.28 * soft(p, C - vec2(0.0, 10.0 * u * uP[6]), 30.0 * u * uP[6], 5.0 * u) * d);
    a = overP(a, t * uP[5]);
  }
  if (uP[7] > 0.001) {
    float o = hole + 12.0 * u;
    float k = clamp(dot(p - C + o, vec2(1.0)) / (4.0 * o), 0.0, 1.0);
    a = over(a, mix(RGB(200.0, 200.0, 206.0), RGB(58.0, 58.0, 62.0), k), uP[7] * (disc(p, C, o) - disc(p, C, hole - 12.0 * u)));
  }
  return overP(a, nameAt(p));
}
"""

private const val APERTURE = """
vec4 stinger(vec2 p) {
  vec2 C = uSize * 0.5;
  float u = uP[19];
  float kk = uP[3];
  vec4 a = vec4(0.0);
  for (int i = 0; i < 6; i++) {
    vec2 l = rot(p - C, -(float(i) * 60.0 + uP[1])) - vec2(0.0, uP[0]);
    vec3 fill = mod(float(i), 2.0) < 0.5 ? uCol[1] : uCol[0];
    a = over(a, fill, rect(l, vec4(-2000.0 * kk, -3000.0 * kk, 4000.0 * kk, 3000.0 * kk)));
    if (uP[2] > 0.001) a = over(a, uCol[2], uP[2] * rect(l, vec4(-2000.0 * kk, -4.0 * u, 4000.0 * kk, 4.0 * u)));
  }
  return overP(a, nameAt(p));
}
"""

private const val ROUTE = """
vec4 stinger(vec2 p) {
  vec2 C = uSize * 0.5;
  float u = uP[19];
  vec4 a = vec4(0.0);
  if (uP[0] > 0.0005 && uP[1] > 0.001) {
    vec4 st = texture2D(uStroke, p / uSize);
    float progress = st.a > 0.0 ? st.r / st.a : 1.0;
    a = over(a, uCol[0], clamp(400.0 * (min(uP[0], 1.0) - progress) + 1.0, 0.0, 1.0) * st.a * uP[1]);
  }
  if (uP[2] > 0.5) a = over(a, uCol[1], disc(p, C, uP[2]));
  if (uP[3] > 0.001) {
    a = over(a, uCol[0], disc(p, C, 18.0 * u * uP[3]));
    a = over(a, uCol[1], disc(p, C, 6.0 * u * uP[3]));
  }
  return overP(a, nameAt(p));
}
"""

private const val VIEWFINDER = """
vec4 stinger(vec2 p) {
  float u = uP[19];
  vec4 a = over(vec4(0.0), uCol[0], rect(p, vec4(uP[0], uP[1], uP[2], uP[3])));
  if (uP[8] > 0.001) {
    float arm = 72.0 * u;
    float t = 5.0 * u;
    float m = 0.0;
    for (int i = 0; i < 4; i++) {
      float sx = i < 2 ? 1.0 : -1.0;
      float sy = (i == 0 || i == 2) ? 1.0 : -1.0;
      float x = sx > 0.0 ? uP[4] : uP[4] + uP[6];
      float y = sy > 0.0 ? uP[5] : uP[5] + uP[7];
      m = max(m, rect(p, vec4(min(x, x + sx * arm), min(y, y + sy * t), arm, t)));
      m = max(m, rect(p, vec4(min(x, x + sx * t), min(y, y + sy * arm), t, arm)));
    }
    a = over(a, uCol[1], uP[8] * m);
  }
  return overP(a, nameAt(p));
}
"""

/** ponytail: the goo is a sum of soft-edged drops thresholded like the board's filter, not a real Gaussian blur of the union. */
private const val LIQUID = """
vec2 drop(int i) {
  if (i == 0) return vec2(1080.0, 660.0);
  if (i == 1) return vec2(420.0, 300.0);
  if (i == 2) return vec2(1680.0, 360.0);
  if (i == 3) return vec2(300.0, 980.0);
  if (i == 4) return vec2(1500.0, 1060.0);
  if (i == 5) return vec2(820.0, 1180.0);
  if (i == 6) return vec2(2000.0, 900.0);
  if (i == 7) return vec2(640.0, 640.0);
  return vec2(1360.0, 140.0);
}
vec4 stinger(vec2 p) {
  float sg = 2.0 * uP[18];
  float f0 = 0.0;
  float f1 = 0.0;
  for (int i = 0; i < 9; i++) {
    float d = length(p - (drop(i) - 120.0) / vec2(1920.0, 1080.0) * uSize);
    if (uP[i] > 0.5) f0 += 1.0 - smoothstep(uP[i] - sg, uP[i] + sg, d);
    if (uP[i + 9] > 0.5) f1 += 1.0 - smoothstep(uP[i + 9] - sg, uP[i + 9] + sg, d);
  }
  vec4 a = over(vec4(0.0), uCol[0], clamp(min(f0, 1.0) * 36.0 - 14.0, 0.0, 1.0));
  a = over(a, uCol[1], clamp(min(f1, 1.0) * 36.0 - 14.0, 0.0, 1.0));
  return overP(a, nameAt(p));
}
"""

private const val RIPPLE = """
vec4 stinger(vec2 p) {
  vec2 C = uSize * 0.5;
  vec4 a = vec4(0.0);
  for (int i = 0; i < 4; i++) {
    float r = uP[2 * i];
    float h = uP[2 * i + 1];
    if (r > 0.0) a = over(a, uCol[i], disc(p, C, r) - (h > 0.5 ? disc(p, C, h) : 0.0));
  }
  return overP(a, nameAt(p));
}
"""

private const val TUNNEL = """
vec4 stinger(vec2 p) {
  vec2 C = uSize * 0.5;
  float u = uP[19];
  vec2 hs = (uSize + 220.0 * u) * 0.5;
  float rad = min(72.0 * u, min(hs.x, hs.y));
  vec4 a = vec4(0.0);
  for (int i = 0; i < 5; i++) {
    float sc = uP[2 * i];
    if (sc > 0.001) {
      vec2 q = abs(rot(p - C, -uP[2 * i + 1]) / sc) - hs + rad;
      float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
      a = over(a, uCol[i], clamp(0.5 - sdf * sc, 0.0, 1.0));
    }
  }
  return overP(a, nameAt(p));
}
"""

/** ponytail: the board screens the blobs against the camera; here they screen each other and sit over it with normal alpha (as iOS). */
private const val BURN = """
vec4 stinger(vec2 p) {
  vec2 C = uSize * 0.5;
  vec4 a = vec4(0.0);
  for (int i = 0; i < 3; i++) {
    float r = uP[3 * i + 2];
    if (r > 0.0) {
      float al = clamp(1.0 - length(p - vec2(uP[3 * i], uP[3 * i + 1])) / r, 0.0, 1.0);
      vec4 b = vec4(uCol[i] * al, al);
      a = a + b - a * b;
    }
  }
  if (uP[9] > 0.001) a = over(a, mix(vec3(1.0), uCol[3], clamp(length(p - C) / (0.35 * length(uSize)), 0.0, 1.0)), uP[9]);
  return overP(a, nameAt(p));
}
"""

fun StingerKind.fragmentShader(): String = PRELUDE + when (this) {
    StingerKind.Lens -> LENS
    StingerKind.Aperture -> APERTURE
    StingerKind.Route -> ROUTE
    StingerKind.Viewfinder -> VIEWFINDER
    StingerKind.Liquid -> LIQUID
    StingerKind.Ripple -> RIPPLE
    StingerKind.Tunnel -> TUNNEL
    StingerKind.Burn -> BURN
} + MAIN
