#version 460 core

// "Hyperspace" renderer: classic light-speed streaks, computed per pixel
// (hyperspace_streaks.glsl). The app stacks its gradient overlays on top
// (StarfieldSimulationWidget); the screen saver has its own look
// (hyperspace_saver.frag).

#include <flutter/runtime_effect.glsl>
#include <hyperspace_streaks.glsl>

uniform vec2 uSize;      // logical pixels
uniform float uDensity;  // probability that a cell holds a star (0..1)
uniform vec4 uShift;     // per layer: scroll offset in rho (wrapped on the CPU)
uniform vec4 uLength;    // per layer: streak length in rho

out vec4 fragColor;

void main() {
  fragColor = hyperspaceStreaks(FlutterFragCoord().xy, uSize, uDensity, uShift, uLength, 0.0, 1.0, 1.0, 0.0, 0.0);
}
