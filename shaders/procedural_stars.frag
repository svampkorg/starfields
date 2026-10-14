#version 460 core

// "Procedural" renderer: the whole starfield computed per pixel, no star data.
//
// Log-polar idea: describe a point by its angle theta and rho = ln(distance
// from the center). A star moves along a fixed theta while its distance grows
// as r0 * e^(k t), so its rho = ln r0 + k t grows LINEARLY. All stars with the
// same speed therefore slide outward together: one grid of cells in
// (theta, rho) that simply scrolls. Each of the 10 speeds is one layer.
//
// Each cell holds 0..kMaxPerCell stars whose existence and position inside the
// cell come from a hash of (layer, cell, slot) - no stored data. For a pixel,
// only the cells near it can reach it (cell sizes are chosen on the CPU so a
// glow never extends past the neighbouring cell), so the work per pixel is
// bounded: layers x 2 angular cells x 4 rows x stars per cell.
//
// Positions are in normalized screen space (each axis -0.5..0.5, like the CPU
// Starfield); glows and tails are measured in logical pixels.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;          // logical pixels
uniform float uScale;        // shader pixels per logical pixel (resolution scaling)
// Explosion: x = seconds since it started (-1: none), y = seconds until the
// burst. Same rules as the CPU Starfield: spawning stops, stars still near the
// center are absorbed, and at the burst they all come out of the core.
uniform vec2 uExplosion;
// Per layer: x = cell size (rho and theta), y = angular cell count,
// z = scroll offset in rho, w = expected stars per cell (steady mode).
uniform vec4 uLayer[10];
// Per layer: x = k (rho per second), y = size growth per second,
// z = largest glow reach (radians, and rho) - neighbours further away are skipped,
// w = expected stars per cell in the burst band of an explosion.
uniform vec4 uMotion[10];

out vec4 fragColor;

const int kLayers = 10;
const int kMaxPerCell = 4;
const float kRowPeriod = 4096.0;  // row hash period; the CPU wraps the scroll offset to match
const float kTwoPi = 6.28318530718;

const vec4 kWhite = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 kRed = vec4(1.0, 0.3216, 0.3216, 1.0);  // Colors.redAccent
const vec4 kClear = vec4(0.0);

vec4 gradient(float t, float midStop) {
  vec4 c = t < midStop ? mix(kWhite, kRed, t / midStop) : mix(kRed, kClear, (t - midStop) / (1.0 - midStop));
  return vec4(c.rgb * c.a, c.a);
}

// Hash without sine (Dave Hoskins): 4 inputs -> 3 values in [0, 1).
vec3 hash34(vec4 p) {
  vec4 p4 = fract(p * vec4(0.1031, 0.1030, 0.0973, 0.1099));
  p4 += dot(p4, p4.wzxy + 33.33);
  return fract((p4.xxy + p4.yzz) * p4.zyx);
}

vec4 over(vec4 top, vec4 bottom) { return top + bottom * (1.0 - top.a); }

void main() {
  vec2 p = FlutterFragCoord().xy / uScale;
  vec2 center = uSize * 0.5;
  vec2 dn = (p - center) / uSize;  // pixel in normalized space
  float rho = log(max(length(dn), 1e-6));
  float theta = atan(dn.y, dn.x) + kTwoPi * 0.5;  // 0 .. 2pi

  vec4 glows = kClear;
  vec4 tails = kClear;

  for (int s = 0; s < kLayers; s++) {
    vec4 layer = uLayer[s];
    vec4 motion = uMotion[s];
    float cell = layer.x;
    float cells = layer.y;
    float dTheta = kTwoPi / cells;
    float u = theta / dTheta;
    float i0 = floor(u);
    float iSide = fract(u) < 0.5 ? -1.0 : 1.0;  // the nearer neighbouring column
    // Only glows cross into a neighbouring column or the row inward, and only
    // for pixels within a glow's reach of that edge.
    float reach = motion.z;
    bool needSide = min(fract(u), 1.0 - fract(u)) * dTheta < reach;
    float rowU = (rho - layer.z) / cell;
    float j0 = floor(rowU);
    bool needInward = fract(rowU) * cell < reach;

    for (int a = 0; a < 2; a++) {
      if (a == 1 && !needSide) break;
      float i = mod(i0 + (a == 0 ? 0.0 : iSide) + cells, cells);
      // One row inward (glows), own row, two rows outward (tails point inward).
      for (int b = -1; b <= 2; b++) {
        if (b == -1 && !needInward) continue;
        float j = j0 + float(b);
        float rowRho = j * cell + layer.z;  // rho of the row's lower edge now

        bool exploding = uExplosion.x >= 0.0;
        float slots = exploding ? max(layer.w, motion.w) : layer.w;

        for (int m = 0; m < kMaxPerCell; m++) {
          if (float(m) >= slots) break;
          vec3 h = hash34(vec4(float(s), i, mod(j, kRowPeriod), float(m)));

          float starTheta = (i + h.y) * dTheta;
          float starRho = rowRho + h.z * cell;
          vec2 dir = vec2(cos(starTheta - kTwoPi * 0.5), sin(starTheta - kTwoPi * 0.5));
          vec2 d = exp(starRho) * dir;
          if (max(abs(d.x), abs(d.y)) > 0.7) continue;  // left the screen

          // Which population this star slot belongs to decides its density.
          float expected = layer.w;
          float growLimit = 1e9;
          if (exploding) {
            float age = uExplosion.x;
            float atStart = max(abs(d.x), abs(d.y)) * exp(-motion.x * age);
            if (atStart >= 0.015) {
              // Already growing when the explosion started: keeps flying.
            } else if (age < uExplosion.y) {
              expected = 0.0;  // absorbed into the core / spawning stopped
            } else {
              float sinceBurst = age - uExplosion.y;
              float atBurst = length(d) * exp(-motion.x * sinceBurst);
              if (atBurst >= 0.004 && atBurst <= 0.03) {
                expected = motion.w;  // burst out of the core
                growLimit = sinceBurst;
              } else if (atBurst > 0.03) {
                expected = 0.0;
              }  // else: spawned after the burst, steady
            }
          }
          if (h.x >= expected - float(m)) continue;  // fractional chance for the last slot

          // Size grows once the star is 0.015 from the center on either axis.
          float growRho = log(0.015 / max(abs(dir.x), abs(dir.y)));
          float growing = min((starRho - growRho) / motion.x, growLimit);
          float size = 0.1 + motion.y * max(0.0, growing);

          vec2 star = center + d * uSize;
          vec2 toPixel = p - star;

          // Glow: visible radius 4 * size (80 % of 5 * size).
          float g = length(toPixel) / (4.0 * size);
          if (g < 1.0) glows = over(gradient(g, 0.25), glows);

          // Tail toward the center, width = size, antialiased; sub-pixel
          // tails are skipped like in the CPU renderers.
          if (size >= 0.25) {
            vec2 toCenter = center - star;
            float dist = length(toCenter);
            if (dist > 0.5) {
              vec2 axis = toCenter / dist;
              float len = min(size * 10.0 + 20.0, dist);
              float along = dot(toPixel, axis) / len;
              if (along >= 0.0 && along <= 1.0) {
                float across = abs(dot(toPixel, vec2(-axis.y, axis.x)));
                // Antialiasing ramp of one shader pixel.
                float halfWidth = size * 0.5;
                float edge = 0.5 / uScale;
                float coverage = clamp((halfWidth + edge - across) * uScale, 0.0, 1.0) * min(1.0, halfWidth / edge);
                if (coverage > 0.0) tails = over(gradient(along, 0.6) * coverage, tails);
              }
            }
          }
        }
      }
    }
  }

  // Tails on top of glows, like the CPU renderers.
  fragColor = over(tails, glows);
}
