#version 460 core

// The native screen saver's Procedural look (macos_saver_metal/): the app's
// Procedural stars (procedural_stars.glsl), colored by speed - the fastest
// near white, then blue, the slowest red - reddening towards the edges, and
// emerging small and faint from the center, so the middle stays dark (a
// bright center saves no screens). The app draws every star white -> red and
// tints them with its gradient overlays.
//
// Not used by the app; tool/build_metal_saver.sh compiles it to Metal with
// impellerc. Uniforms (declared in procedural_stars.glsl) are bound in
// declaration order (buffer 0, 1, ...).

#include <flutter/runtime_effect.glsl>
#define PROCEDURAL_SAVER_LOOK
#include <procedural_stars.glsl>

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy / uScale;
  fragColor = vec4(proceduralStars(p).rgb, 1.0);  // premultiplied over black
}
