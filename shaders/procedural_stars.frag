#version 460 core

// "Procedural" renderer: the whole starfield computed per pixel, no star data
// (procedural_stars.glsl). The app stacks its gradient overlays on top
// (StarfieldSimulationWidget); the screen saver has its own look
// (procedural_saver.frag).

#include <flutter/runtime_effect.glsl>
#include <procedural_stars.glsl>

out vec4 fragColor;

void main() {
  fragColor = proceduralStars(FlutterFragCoord().xy / uScale);
}
