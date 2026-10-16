// Metal port of shaders/hyperspace.frag for the native screen saver
// (StarfieldsMetalSaverView.swift). Keep the two in step: same constants,
// same hash, same math. Compiled at runtime from source (no offline Metal
// toolchain needed).
//
// Differences to the GLSL version:
// - FlutterFragCoord() (logical pixels) is the fragment position in device
//   pixels divided by uScale.
// - One full-screen triangle from the vertex id instead of Flutter's
//   drawRect.
// - The two full-screen overlays that StarfieldSimulationWidget stacks on top
//   (a hue-blended radial gradient and the hardLight core,
//   ScalingGradientWidget) are computed here, after the streaks. Flutter
//   blends sRGB-encoded values without linearizing; so does this shader (the
//   target is bgra8Unorm, not _sRGB).

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
  float2 size;     // logical pixels
  float density;   // probability that a cell holds a star (0..1)
  float scale;     // device pixels per logical pixel
  float4 shift;    // per layer: scroll offset in rho (wrapped on the CPU)
  float4 length;   // per layer: streak length in rho
};

constant int kLayers = 4;
constant float kColumns = 1024.0;
constant float kRow = 0.35;
constant float kRowPeriod = 4096.0;
constant float kTwoPi = 6.28318530718;
constant float kFadeStart = -4.8;
constant float kFadeEnd = -3.2;

// GLSL mod (floored), not fmod (truncated): differs for negative rows.
static float glslMod(float x, float y) { return x - y * floor(x / y); }

static float3 hash34(float4 p) {
  float4 p4 = fract(p * float4(0.1031, 0.1030, 0.0973, 0.1099));
  p4 += dot(p4, p4.wzxy + 33.33);
  return fract((p4.xxy + p4.yzz) * p4.zyx);
}

// --- Overlays -------------------------------------------------------------

struct Stop {
  float at;
  float4 color;  // unpremultiplied sRGB
};

static float4 rgba(uint argb, float alpha = 1.0) {
  return float4(float((argb >> 16) & 0xFF), float((argb >> 8) & 0xFF), float(argb & 0xFF), 255.0) / 255.0 *
         float4(1.0, 1.0, 1.0, alpha);
}

// Flutter's RadialGradient with TileMode.clamp: t is the distance from the
// center in units of the radius. Colors interpolate unpremultiplied.
template <int N>
static float4 gradient(float t, const thread Stop (&stops)[N]) {
  if (t <= stops[0].at) return stops[0].color;
  for (int i = 1; i < N; i++) {
    if (t <= stops[i].at) {
      float f = (t - stops[i - 1].at) / (stops[i].at - stops[i - 1].at);
      return mix(stops[i - 1].color, stops[i].color, f);
    }
  }
  return stops[N - 1].color;
}

// Non-separable blend helpers (W3C compositing spec).
static float lum(float3 c) { return dot(c, float3(0.3, 0.59, 0.11)); }

static float3 clipColor(float3 c) {
  float l = lum(c);
  float n = min(c.r, min(c.g, c.b));
  float x = max(c.r, max(c.g, c.b));
  if (n < 0.0) c = l + (c - l) * l / (l - n);
  if (x > 1.0) c = l + (c - l) * (1.0 - l) / (x - l);
  return c;
}

static float3 setLum(float3 c, float l) { return clipColor(c + (l - lum(c))); }

static float sat(float3 c) { return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)); }

static float3 setSat(float3 c, float s) {
  float n = min(c.r, min(c.g, c.b));
  float x = max(c.r, max(c.g, c.b));
  return x > n ? (c - n) * s / (x - n) : float3(0.0);
}

// Source `s` (unpremultiplied, alpha s.a) blended onto an opaque backdrop.
static float3 blendHue(float3 backdrop, float4 s) {
  float3 b = setLum(setSat(s.rgb, sat(backdrop)), lum(backdrop));
  return mix(backdrop, b, s.a);
}

static float3 blendHardLight(float3 backdrop, float4 s) {
  float3 multiply = backdrop * 2.0 * s.rgb;
  float3 screen = 1.0 - (1.0 - backdrop) * (1.0 - (2.0 * s.rgb - 1.0));
  float3 b = select(screen, multiply, s.rgb <= 0.5);
  return mix(backdrop, b, s.a);
}

static float3 overlays(float3 color, float2 p, float2 size) {
  // RadialGradient radius is a fraction of the shortest side.
  float dist = length(p - size * 0.5) / min(size.x, size.y);

  // StarfieldSimulationWidget: BlendMode.hue, radius 0.7.
  const Stop tint[6] = {
      {0.0, rgba(0xFFFFFF)},        // white
      {0.3, rgba(0x18FFFF)},        // cyanAccent
      {0.5, rgba(0x03A9F4)},        // lightBlue
      {0.6, rgba(0x448AFF)},        // blueAccent
      {0.8, rgba(0x673AB7)},        // deepPurple
      {1.0, rgba(0x673AB7, 0.4)},   // deepPurple, 40 %
  };
  color = blendHue(color, gradient(dist / 0.7, tint));

  // ScalingGradientWidget (scale 1): BlendMode.hardLight, radius 1.5.
  const Stop core[3] = {
      {0.02, rgba(0xFFFFFF)},       // white
      {0.2, rgba(0x2196F3)},        // blue
      {1.0, float4(0.0)},           // transparent (black, alpha 0)
  };
  return blendHardLight(color, gradient(dist / 1.5, core));
}

// --- Streaks and composition -----------------------------------------------

vertex float4 fullScreenVertex(uint id [[vertex_id]]) {
  // A triangle covering the whole clip space: (-1,-1), (3,-1), (-1,3).
  float2 uv = float2((id << 1) & 2, id & 2);
  return float4(uv * 2.0 - 1.0, 0.0, 1.0);
}

fragment float4 hyperspaceFragment(float4 position [[position]], constant Uniforms& u [[buffer(0)]]) {
  float2 p = position.xy / u.scale;
  float scale = min(u.size.x, u.size.y);
  float2 d = (p - u.size * 0.5) / scale;
  float r = max(length(d), 1e-6);
  float rho = log(r);
  float rPx = r * scale;
  float uCol = (atan2(d.y, d.x) + kTwoPi * 0.5) / kTwoPi * kColumns;
  float column = floor(uCol);
  float dTheta = kTwoPi / kColumns;

  float4 color = float4(0.0);
  for (int layer = 0; layer < kLayers; layer++) {
    float shift = u.shift[layer];
    float len = u.length[layer];
    float row0 = floor((rho - shift) / kRow);
    for (int b = 0; b < 3; b++) {
      float row = row0 + float(b);
      float3 h = hash34(float4(float(layer), column, glslMod(row, kRowPeriod), 7.0));
      if (h.x >= u.density) continue;

      float head = (row + h.z) * kRow + shift;
      float along = (rho - (head - len)) / len;
      if (along < 0.0 || along > 1.0) continue;

      float offset = (uCol - column - (0.25 + 0.5 * h.y)) * dTheta * rPx;
      float halfWidth = min(0.25 * dTheta * rPx, 0.3 + rPx * 0.0012);
      float coverage = clamp(halfWidth + 0.5 - abs(offset), 0.0, 1.0) * min(1.0, 2.0 * halfWidth);

      float fade = smoothstep(kFadeStart, kFadeEnd, head);
      float intensity = along * along * coverage * fade * (0.55 + 0.45 * h.y);
      float3 tint = mix(float3(0.55, 0.75, 1.0), float3(1.0), along);
      float4 streak = float4(tint * intensity, intensity);
      color = streak + color * (1.0 - streak.a);
    }
  }
  // Premultiplied over the black background, then the overlays.
  return float4(overlays(color.rgb, p, u.size), 1.0);
}
