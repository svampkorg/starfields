#version 460 core

// "Hyperspace" renderer: classic light-speed streaks, computed per pixel.
//
// Same log-polar idea as procedural_stars.frag (angle theta, rho = ln
// distance; outward exponential motion = constant scrolling in rho), but a
// look built for shaders: every star is a thin radial streak, a short segment
// of fixed length in rho. Streaks never leave their angular column and span
// at most three rows, so each pixel checks exactly kLayers * 3 cells whatever
// the star count - the cost is constant. The star count only changes the
// probability that a cell holds a star (uDensity).

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // logical pixels
uniform float uDensity;  // probability that a cell holds a star (0..1)
uniform vec4 uShift;     // per layer: scroll offset in rho (wrapped on the CPU)
uniform vec4 uLength;    // per layer: streak length in rho

out vec4 fragColor;

const int kLayers = 4;
const float kColumns = 1024.0;
const float kRow = 0.35;          // row height in rho; streaks are at most 2 rows long
const float kRowPeriod = 4096.0;  // row hash period; the CPU wraps uShift to match
const float kTwoPi = 6.28318530718;
const float kFadeStart = -4.8;    // rho where streaks appear out of the center
const float kFadeEnd = -3.2;

vec3 hash34(vec4 p) {
  vec4 p4 = fract(p * vec4(0.1031, 0.1030, 0.0973, 0.1099));
  p4 += dot(p4, p4.wzxy + 33.33);
  return fract((p4.xxy + p4.yzz) * p4.zyx);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float scale = min(uSize.x, uSize.y);
  vec2 d = (p - uSize * 0.5) / scale;  // isotropic: streaks are radial on screen
  float r = max(length(d), 1e-6);
  float rho = log(r);
  float rPx = r * scale;
  float u = (atan(d.y, d.x) + kTwoPi * 0.5) / kTwoPi * kColumns;
  float column = floor(u);
  float dTheta = kTwoPi / kColumns;

  vec4 color = vec4(0.0);
  for (int layer = 0; layer < kLayers; layer++) {
    float shift = uShift[layer];
    float len = uLength[layer];
    float row0 = floor((rho - shift) / kRow);
    // The streak's head is in this row or up to two rows further out.
    for (int b = 0; b < 3; b++) {
      float row = row0 + float(b);
      vec3 h = hash34(vec4(float(layer), column, mod(row, kRowPeriod), 7.0));
      if (h.x >= uDensity) continue;

      float head = (row + h.z) * kRow + shift;  // rho of the streak's head
      float along = (rho - (head - len)) / len;   // 0 at the tail end .. 1 at the head
      if (along < 0.0 || along > 1.0) continue;

      // Keep the streak in the middle half of its column so it never crosses
      // into a neighbour; width grows with distance (perspective).
      float offset = (u - column - (0.25 + 0.5 * h.y)) * dTheta * rPx;  // pixels across
      float halfWidth = min(0.25 * dTheta * rPx, 0.3 + rPx * 0.0012);
      float coverage = clamp(halfWidth + 0.5 - abs(offset), 0.0, 1.0) * min(1.0, 2.0 * halfWidth);

      float fade = smoothstep(kFadeStart, kFadeEnd, head);
      float intensity = along * along * coverage * fade * (0.55 + 0.45 * h.y);
      vec3 tint = mix(vec3(0.55, 0.75, 1.0), vec3(1.0), along);  // blue tail, white head
      vec4 streak = vec4(tint * intensity, intensity);
      color = streak + color * (1.0 - streak.a);
    }
  }
  fragColor = color;
}
