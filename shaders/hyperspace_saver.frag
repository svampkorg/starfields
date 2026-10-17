#version 460 core

// The native screen saver's look (macos_saver_metal/): light-speed streaks
// (hyperspace_streaks.glsl) with a glow, on black; streaks emerge thin and
// faint near the center, so the middle stays dark - a bright center saves no
// screens.
//
// Not used by the app; tool/build_metal_saver.sh compiles it to Metal with
// impellerc. Uniforms are bound in declaration order (buffer 0, 1, ...).

#include <flutter/runtime_effect.glsl>
#include <hyperspace_streaks.glsl>

uniform vec2 uSize;      // logical pixels
uniform float uDensity;  // probability that a cell holds a star (0..1)
uniform vec4 uShift;     // per layer: scroll offset in rho (wrapped on the CPU)
uniform vec4 uLength;    // per layer: streak length in rho
uniform float uGlow;     // halo strength around the streaks
uniform float uWidth;    // streak core width factor
uniform float uBoost;    // streak brightness factor

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  // Streaks emerge: they start thin and faint and grow on their way out, so
  // the center stays dark without a fixed mask.
  vec4 streaks = hyperspaceStreaks(p, uSize, uDensity, uShift, uLength, uGlow, uWidth, uBoost, 1.0);

  fragColor = vec4(streaks.rgb, 1.0);  // premultiplied over black
}
