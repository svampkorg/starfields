#version 460 core

// Paints the texture atlas of the "Styled" renderer, once at start-up
// (drawRect into a picture -> image). Every frame the painter then draws all
// glows and tails as textured quads that sample this atlas.
//
// Why an atlas and not a per-star shader: Impeller evaluates a FragmentShader
// used with drawVertices + texture coordinates into an offscreen texture that
// covers the texture coordinate bounds (one texel per unit, <= 16384 wide),
// then maps that texture onto the triangles. The shader never runs per screen
// pixel there, so per-star data cannot be passed through texture coordinates.
//
// Layout (pixels):
//   y 0 .. 256            glow disc, radius 128 = the visible glow radius
//   y 256 + 20k .. +20    tail strip for width class k (k = 0..31):
//                           half-width (k + 1) / 4 px, x = along the tail
//                           (0 = star, 256 = end), y = across the tail,
//                           spanning half-width + 1 px edge on each side.

#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

const float kGlow = 256.0;
const float kBandHeight = 20.0;

const vec4 kWhite = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 kRed = vec4(1.0, 0.3216, 0.3216, 1.0);  // Colors.redAccent
const vec4 kClear = vec4(0.0, 0.0, 0.0, 0.0);      // Colors.transparent

// Three-stop gradient, interpolated unpremultiplied like Flutter's gradients.
vec4 gradient(float t, float midStop) {
  vec4 c = t < midStop ? mix(kWhite, kRed, t / midStop) : mix(kRed, kClear, (t - midStop) / (1.0 - midStop));
  return vec4(c.rgb * c.a, c.a);  // premultiply
}

void main() {
  vec2 p = FlutterFragCoord().xy;

  if (p.y < kGlow) {
    // Glow: white -> redAccent at 25 % -> transparent at the visible radius
    // (the original 0 / 20 % / 80 % stops of the full glow radius).
    float d = length(p - vec2(kGlow / 2.0)) / (kGlow / 2.0);
    fragColor = d < 1.0 ? gradient(d, 0.25) : kClear;
    return;
  }

  float band = floor((p.y - kGlow) / kBandHeight);
  float halfWidth = (band + 1.0) / 4.0;
  // Across the strip in pixels of the drawn tail: -(halfWidth + 1) .. +(halfWidth + 1).
  float v = (p.y - kGlow - band * kBandHeight) / kBandHeight;
  float across = (v * 2.0 - 1.0) * (halfWidth + 1.0);
  float along = p.x / kGlow;

  // Antialiased edges: full coverage inside, 1 px ramp at the border; thin
  // tails fade with their width instead of breaking up into dots.
  float coverage = clamp(halfWidth + 0.5 - abs(across), 0.0, 1.0) * min(1.0, 2.0 * halfWidth);
  fragColor = gradient(along, 0.6) * coverage;
}
