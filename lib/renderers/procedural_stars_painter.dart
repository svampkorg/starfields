import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:starfields/renderers/procedural_layers.dart';
import 'package:starfields/starfield/starfield.dart';

/// Draws the whole starfield with one full-screen fragment shader
/// (`shaders/procedural_stars.frag`). No per-star data: the [Starfield] is
/// only used for its settings (count, speed, explosion and its start time).
class ProceduralStarsPainter extends CustomPainter {
  final Starfield starfield;
  final ui.FragmentShader shader;
  final ValueListenable<double> time;

  /// Resolution of the shader relative to logical pixels. The image is then
  /// drawn scaled to the screen. 1.0 on a 2x display = half resolution per
  /// axis, a quarter of the shader work.
  final double renderScale;

  final ProceduralLayers layers = ProceduralLayers();
  final Paint _shaderPaint = Paint();
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;

  /// Size of the last paint, used to estimate [ProceduralLayers.effectiveStars]
  /// outside of painting.
  Size lastSize = Size.zero;

  ProceduralStarsPainter({required this.starfield, required this.shader, required this.time, this.renderScale = 1})
    : super(repaint: time);

  /// Effective star count for [count] stars on the last painted size.
  double estimateStars() {
    _compute(lastSize);
    return layers.effectiveStars;
  }

  void _compute(Size size) {
    layers.compute(
      count: starfield.count,
      tickSeconds: starfield.tickSeconds,
      explode: !starfield.respawn,
      age: time.value - starfield.startTime,
      size: size,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    lastSize = size;
    _compute(size);
    var i = 0;
    shader
      ..setFloat(i++, size.width)
      ..setFloat(i++, size.height)
      ..setFloat(i++, renderScale)
      ..setFloat(i++, starfield.respawn ? 0 : 1)
      ..setFloat(i++, time.value - starfield.startTime)
      ..setFloat(i++, starfield.count / ProceduralLayers.layers);
    for (final value in layers.layer) {
      shader.setFloat(i++, value);
    }
    for (final value in layers.motion) {
      shader.setFloat(i++, value);
    }
    _shaderPaint.shader = shader;

    // Render the shader at renderScale into an offscreen image, then draw it
    // stretched over the full size.
    final width = (size.width * renderScale).ceil(), height = (size.height * renderScale).ceil();
    if (width == 0 || height == 0) return;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), _shaderPaint);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Offset.zero & size,
      _imagePaint,
    );
    image.dispose();
  }

  @override
  bool shouldRepaint(ProceduralStarsPainter oldDelegate) => oldDelegate.starfield != starfield;
}
