// The Procedural renderer's stars, shared by the app (procedural_stars.frag)
// and the native screen saver (procedural_saver.frag, compiled to Metal by
// tool/build_metal_saver.sh). Declares the uniforms; include it after
// <flutter/runtime_effect.glsl>. Define PROCEDURAL_SAVER_LOOK before the
// include for the saver's look.

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

#ifndef PROCEDURAL_STARS_GLSL_
#define PROCEDURAL_STARS_GLSL_

uniform vec2 uSize;          // logical pixels
uniform float uScale;        // shader pixels per logical pixel (resolution scaling)
// Explosion: x = seconds since it started (-1: none), y = seconds until the
// burst, z = pause after the burst, w = unused. Same rules as the CPU
// Starfield: spawning stops, stars still near the center are absorbed, at the
// burst they all come out of the core, and after the pause births come back
// gradually. (A vec4, not a vec3: a vec3 before the vec4 arrays broke the
// uniform layout - the whole shader rendered magenta.)
uniform vec4 uExplosion;
// Per layer: x = cell size (rho and theta), y = angular cell count,
// z = scroll offset in rho, w = expected stars per cell (steady mode).
uniform vec4 uLayer[10];
// Per layer: x = k (rho per second), y = size growth per second,
// z = largest glow reach (radians, and rho) - neighbours further away are skipped,
// w = expected stars per cell in the burst band of an explosion.
uniform vec4 uMotion[10];
#ifdef PROCEDURAL_SAVER_LOOK
// Which stars: the screen saver gives each display its own. Declared last,
// so the app's uniform layout is unchanged.
uniform float uSeed;
#else
const float uSeed = 0.0;
#endif


const int kLayers = 10;
const int kMaxPerCell = 4;
const float kRowPeriod = 4096.0;  // row hash period; the CPU wraps the scroll offset to match
const float kTwoPi = 6.28318530718;
const float kBirthRho = -9.7;        // typical rho at birth (~1e-4 from the center)
const float kComebackSeconds = 3.0;  // birth ramp after the pause (Starfield.comebackRampSeconds)

const vec4 kWhite = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 kRed = vec4(1.0, 0.3216, 0.3216, 1.0);  // Colors.redAccent
const vec4 kClear = vec4(0.0);

// White core -> the star's color at midStop -> clear.
vec4 gradient(float t, float midStop, vec3 color) {
  vec4 c = t < midStop ? mix(kWhite, vec4(color, 1.0), t / midStop)
                       : mix(vec4(color, 1.0), kClear, (t - midStop) / (1.0 - midStop));
  return vec4(c.rgb * c.a, c.a);
}

#ifdef PROCEDURAL_SAVER_LOOK
// The screen saver's look (procedural_saver.frag): the hue follows the
// layer's speed - the fastest (closest) stars near white, then blue, the
// slowest red - and every star reddens towards the edges and emerges small
// and faint from the center (see the star loop).
vec3 starColor(int layer) {
  float speed = float(layer) / float(kLayers - 1);  // 0 slowest .. 1 fastest
  vec3 red = kRed.rgb;
  vec3 blue = vec3(0.32, 0.55, 1.0);
  vec3 nearWhite = vec3(0.85, 0.92, 1.0);
  return speed < 0.5 ? mix(red, blue, speed / 0.5) : mix(blue, nearWhite, (speed - 0.5) / 0.5);
}
#else
// The app's colors: every star white -> red.
vec3 starColor(int layer) { return kRed.rgb; }
#endif

// Hash without sine (Dave Hoskins): 4 inputs -> 3 values in [0, 1).
vec3 hash34(vec4 p) {
  vec4 p4 = fract(p * vec4(0.1031, 0.1030, 0.0973, 0.1099));
  p4 += dot(p4, p4.wzxy + 33.33);
  return fract((p4.xxy + p4.yzz) * p4.zyx);
}

vec4 over(vec4 top, vec4 bottom) { return top + bottom * (1.0 - top.a); }

// Premultiplied color of the stars at [p] (logical pixels).
vec4 proceduralStars(vec2 p) {
  vec2 center = uSize * 0.5;
  vec2 dn = (p - center) / uSize;  // pixel in normalized space
  float rho = log(max(length(dn), 1e-6));
  float theta = atan(dn.y, dn.x) + kTwoPi * 0.5;  // 0 .. 2pi

  vec4 glows = kClear;
  vec4 tails = kClear;

  for (int s = 0; s < kLayers; s++) {
    vec3 layerColor = starColor(s);
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
          vec3 h = hash34(vec4(float(s), i, mod(j, kRowPeriod), float(m) + uSeed));

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
              } else {
                // Spawned after the burst: none during the pause, then births
                // come back gradually, like the CPU Starfield.
                float bornAfterPause = sinceBurst - uExplosion.z - (starRho - kBirthRho) / motion.x;
                expected *= clamp(bornAfterPause / kComebackSeconds, 0.0, 1.0);
              }
            }
          }
          if (h.x >= expected - float(m)) continue;  // fractional chance for the last slot

          // Size grows once the star is 0.015 from the center on either axis.
          float growRho = log(0.015 / max(abs(dir.x), abs(dir.y)));
          float growing = min((starRho - growRho) / motion.x, growLimit);
          float size = 0.1 + motion.y * max(0.0, growing);

#ifdef PROCEDURAL_SAVER_LOOK
          // Emerging: small and faint near the center, full from rFull
          // (normalized units), which varies per star - no fixed dark disc.
          float rStar = length(d);
          float rFull = mix(0.12, 0.38, fract(h.y * 7.13 + h.z * 3.71));
          float grown = smoothstep(0.15 * rFull, rFull, rStar);
          size *= mix(0.25, 1.0, grown);
          grown *= grown;  // the opacity fades in more softly than the size
          // Reddening towards the edges.
          vec3 color = mix(layerColor, kRed.rgb, smoothstep(0.3, 0.825, rStar));
#else
          float grown = 1.0;
          vec3 color = layerColor;
#endif

          vec2 star = center + d * uSize;
          vec2 toPixel = p - star;

          // Glow: visible radius 4 * size (80 % of 5 * size).
          float g = length(toPixel) / (4.0 * size);
          if (g < 1.0) glows = over(gradient(g, 0.25, color) * grown, glows);

          // Tail toward the center, width = size, antialiased; sub-pixel
          // tails are skipped like in the CPU renderers.
          if (size >= 0.25) {
            vec2 toCenter = center - star;
            float dist = length(toCenter);
            if (dist > 0.5) {
              vec2 axis = toCenter / dist;
#ifdef PROCEDURAL_SAVER_LOOK
              // Tails reach at most halfway to the center: they no longer all
              // converge there, and the middle stays dark by itself.
              float len = min(size * 10.0 + 20.0, dist * 0.55);
#else
              float len = min(size * 10.0 + 20.0, dist);
#endif
              float along = dot(toPixel, axis) / len;
              if (along >= 0.0 && along <= 1.0) {
                float across = abs(dot(toPixel, vec2(-axis.y, axis.x)));
                // Antialiasing ramp of one shader pixel.
                float halfWidth = size * 0.5;
                float edge = 0.5 / uScale;
                float coverage = clamp((halfWidth + edge - across) * uScale, 0.0, 1.0) * min(1.0, halfWidth / edge);
                if (coverage > 0.0) tails = over(gradient(along, 0.6, color) * (coverage * grown), tails);
              }
            }
          }
        }
      }
    }
  }

  // Tails on top of glows, like the CPU renderers.
  return over(tails, glows);
}

#endif  // PROCEDURAL_STARS_GLSL_
