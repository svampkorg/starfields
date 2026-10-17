// Light-speed streaks on a log-polar grid, shared by the app's Hyperspace
// renderer (hyperspace.frag) and the native screen saver
// (hyperspace_saver.frag, compiled to Metal by tool/build_metal_saver.sh).
//
// Log-polar idea as in procedural_stars.frag (angle theta, rho = ln
// distance; outward exponential motion = constant scrolling in rho): every
// star is a short radial segment of a given length in rho. Streaks never
// leave their angular column and are at most kMaxRows - 1 rows long, so each
// pixel checks a bounded number of cells whatever the star count - the star
// count only changes the probability that a cell holds a star (density).

#ifndef HYPERSPACE_STREAKS_GLSL_
#define HYPERSPACE_STREAKS_GLSL_

const int kLayers = 4;
const float kColumns = 1024.0;
const float kRow = 0.35;          // row height in rho
const int kMaxRows = 8;           // rows checked at most: streaks up to 7 rows long
const float kRowPeriod = 4096.0;  // row hash period; the CPU wraps the shift to match
const float kTwoPi = 6.28318530718;
const float kFadeStart = -4.8;    // rho where streaks appear out of the center
const float kFadeEnd = -3.2;

vec3 hash34(vec4 p) {
  vec4 p4 = fract(p * vec4(0.1031, 0.1030, 0.0973, 0.1099));
  p4 += dot(p4, p4.wzxy + 33.33);
  return fract((p4.xxy + p4.yzz) * p4.zyx);
}

// Premultiplied streak color at [p] (logical pixels) in a [size] view.
//   density: probability that a cell holds a star (0..1)
//   shift:   per layer, scroll offset in rho (wrapped on the CPU)
//   len:     per layer, streak length in rho
//   glow:    strength of a soft halo around each streak
//   width:   core width factor (1: the app's streaks)
//   boost:   brightness factor (1: the app's streaks)
//   emerge:  1 = every streak starts thin and faint and grows into full width
//            and brightness on its way out, each at its own distance (the
//            screen saver's dark center); 0 = off (the app)
// With glow 0 and width 1 only the pixel's own column is checked (the app);
// otherwise the neighbour columns too, so halos and wider cores can spill
// over into them.
vec4 hyperspaceStreaks(vec2 p, vec2 size, float density, vec4 shift, vec4 len, float glow, float width,
                       float boost, float emerge) {
  float scale = min(size.x, size.y);
  vec2 d = (p - size * 0.5) / scale;  // isotropic: streaks are radial on screen
  float r = max(length(d), 1e-6);
  float rho = log(r);
  float rPx = r * scale;
  float u = (atan(d.y, d.x) + kTwoPi * 0.5) / kTwoPi * kColumns;
  float column = floor(u);
  float dTheta = kTwoPi / kColumns;
  int reach = (glow > 0.0 || width > 1.0) ? 1 : 0;
  // Halo width in pixels grows with distance (perspective), like the core.
  float glowWidth = 1.5 + rPx * 0.006;
  // Core half width: in the middle half of the own column, or up to one and
  // a quarter columns when the neighbours are checked too.
  float maxHalfWidth = (reach > 0 ? 1.25 : 0.25) * dTheta * rPx;
  float halfWidth = min(maxHalfWidth, (0.3 + rPx * 0.0012) * width);

  vec4 color = vec4(0.0);
  float halo = 0.0;
  for (int layer = 0; layer < kLayers; layer++) {
    float layerShift = shift[layer];
    float layerLen = len[layer];
    // A streak covers this pixel if its head is between rho and rho + length:
    // rows row0 .. floor((rho - shift + length) / kRow).
    // (float: SkSL, Flutter's other shader target, has no integer min.)
    float rowPos = (rho - layerShift) / kRow;
    float row0 = floor(rowPos);
    float rows = min(float(kMaxRows), floor(rowPos + layerLen / kRow) - row0 + 1.0);
    for (int dc = -1; dc <= 1; dc++) {
      if (dc < -reach || dc > reach) continue;
      float c = column + float(dc);
      float cellColumn = mod(c, kColumns);  // wraps at the atan seam
      for (int b = 0; b < kMaxRows; b++) {
        if (float(b) >= rows) break;
        float row = row0 + float(b);
        vec3 h = hash34(vec4(float(layer), cellColumn, mod(row, kRowPeriod), 7.0));
        if (h.x >= density) continue;

        float head = (row + h.z) * kRow + layerShift;  // rho of the streak's head
        float along = (rho - (head - layerLen)) / layerLen;  // 0 at the tail end .. 1 at the head
        if (along < 0.0 || along > 1.0) continue;

        // Keep the streak in the middle half of its column; width grows with
        // distance (perspective).
        float offset = (u - c - (0.25 + 0.5 * h.y)) * dTheta * rPx;  // pixels across
        float fade = smoothstep(kFadeStart, kFadeEnd, head);
        // Emerging: full size from rFull (in units of the shortest side),
        // which varies per streak, so there is no fixed dark disc.
        float grown = 1.0;
        if (emerge > 0.0) {
          float rFull = mix(0.08, 0.3, fract(h.y * 7.13 + h.z * 3.71));
          grown = mix(1.0, smoothstep(0.2 * rFull, rFull, exp(head)), emerge);
        }
        float brightness = along * along * fade * grown * (0.55 + 0.45 * h.y);
        halo += glow * brightness * exp(-offset * offset / (glowWidth * glowWidth));

        float streakHalfWidth = halfWidth * mix(0.35, 1.0, grown);
        float coverage = clamp(streakHalfWidth + 0.5 - abs(offset), 0.0, 1.0) * min(1.0, 2.0 * streakHalfWidth);
        float intensity = min(1.0, brightness * boost) * coverage;
        vec3 tint = mix(vec3(0.55, 0.75, 1.0), vec3(1.0), along);  // blue tail, white head
        vec4 streak = vec4(tint * intensity, intensity);
        color = streak + color * (1.0 - streak.a);
      }
    }
  }
  // The halo sits under the streaks, in a deeper blue.
  float haloAlpha = min(halo, 1.0);
  return color + vec4(vec3(0.35, 0.55, 1.0) * haloAlpha, haloAlpha) * (1.0 - color.a);
}

#endif  // HYPERSPACE_STREAKS_GLSL_
