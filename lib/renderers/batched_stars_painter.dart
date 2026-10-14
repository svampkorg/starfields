import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:starfields/starfield/starfield.dart';

/// Paints all star glows with a single atlas draw and all tails with a single
/// vertices draw, writing straight into reusable typed buffers.
class BatchedStarsPainter extends CustomPainter {
  final Starfield starfield;
  final ui.Image sprite;

  /// Radius in pixels of the pre-rendered glow sprite.
  static const double spriteRadius = 128;

  /// The glow gradient is transparent beyond this fraction of its radius, so
  /// the sprite only covers that part: no GPU work on invisible pixels.
  static const double _visibleGlow = 0.8;

  /// Tails narrower than this (logical pixels) are skipped. These are the
  /// sub-pixel slivers of stars that have not started growing yet: invisible
  /// under the white core, but thousands of them cost real fill time.
  static const double minTailWidth = 0.25;

  /// Vertices per tail: four triangles, three color stops along the tail.
  static const int _tailVertices = 12;

  static final Int32List _tailColorPattern = () {
    const white = 0xFFFFFFFF, red = 0xFFFF5252, clear = 0x00000000; // Colors.redAccent
    return Int32List.fromList([white, white, red, white, red, red, red, red, clear, red, clear, clear]);
  }();

  // Reusable per-star buffers, grown with the starfield.
  Float32List _transforms = Float32List(0);
  Float32List _rects = Float32List(0);
  Float32List _tailPositions = Float32List(0);
  Int32List _tailColors = Int32List(0);
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _tailPaint = Paint();

  BatchedStarsPainter({required this.starfield, required this.sprite, super.repaint}) {
    _ensureCapacity(starfield.count);
  }

  void _ensureCapacity(int stars) {
    final capacity = _rects.length ~/ 4;
    if (stars <= capacity) return;
    final newCapacity = max(stars, capacity * 2);
    _transforms = Float32List(newCapacity * 4);
    _rects = Float32List(newCapacity * 4);
    _tailPositions = Float32List(newCapacity * _tailVertices * 2);
    _tailColors = Int32List(newCapacity * _tailVertices);
    // Constant per star: the whole sprite, and the tail color stops.
    for (var i = 0; i < newCapacity; i++) {
      _rects.setAll(i * 4, const [0, 0, spriteRadius * 2, spriteRadius * 2]);
      _tailColors.setAll(i * _tailVertices, _tailColorPattern);
    }
  }

  /// Renders the star glow once, so each star can be drawn as a scaled copy.
  static ui.Image createSprite() {
    const center = Offset(spriteRadius, spriteRadius);
    const gradient = RadialGradient(
      colors: [Colors.white, Colors.redAccent, Colors.transparent],
      // Original stops 0.0, 0.2, 0.8 of the glow radius, rescaled to the
      // visible part, which fills the whole sprite.
      stops: [0.0, 0.2 / _visibleGlow, 1.0],
    );
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawCircle(
      center,
      spriteRadius,
      Paint()..shader = gradient.createShader(Rect.fromCircle(center: center, radius: spriteRadius)),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(spriteRadius.toInt() * 2, spriteRadius.toInt() * 2);
    picture.dispose();
    return image;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final count = starfield.visibleCount;
    if (count == 0) return;
    _ensureCapacity(count);
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    for (var i = 0; i < count; i++) {
      final px = centerX + starfield.x[i] * size.width;
      final py = centerY + starfield.y[i] * size.height;
      final starSize = starfield.size[i];

      // Glow: radius starSize * 5 (visible part 80 %), sprite centered on the star.
      final scale = starSize * 5 * _visibleGlow / spriteRadius;
      final t = i * 4;
      _transforms[t] = scale;
      _transforms[t + 1] = 0;
      _transforms[t + 2] = px - scale * spriteRadius;
      _transforms[t + 3] = py - scale * spriteRadius;

      // Tail: a strip of width starSize from the star towards the center,
      // fading white -> red at 60% -> transparent.
      var dx = centerX - px;
      var dy = centerY - py;
      final distance = sqrt(dx * dx + dy * dy);
      var length = 0.0, nx = 0.0, ny = 0.0;
      if (distance > 0.5 && starSize >= minTailWidth) {
        dx /= distance;
        dy /= distance;
        length = min(starSize * 10 + 20, distance);
        nx = -dy * starSize / 2;
        ny = dx * starSize / 2;
      }
      final midX = px + dx * length * 0.6, midY = py + dy * length * 0.6;
      final endX = px + dx * length, endY = py + dy * length;
      final v = i * _tailVertices * 2;
      _setTriangle(v, px + nx, py + ny, px - nx, py - ny, midX + nx, midY + ny);
      _setTriangle(v + 6, px - nx, py - ny, midX - nx, midY - ny, midX + nx, midY + ny);
      _setTriangle(v + 12, midX + nx, midY + ny, midX - nx, midY - ny, endX + nx, endY + ny);
      _setTriangle(v + 18, midX - nx, midY - ny, endX - nx, endY - ny, endX + nx, endY + ny);
    }

    canvas.drawRawAtlas(
      sprite,
      Float32List.sublistView(_transforms, 0, count * 4),
      Float32List.sublistView(_rects, 0, count * 4),
      null,
      null,
      null,
      _spritePaint,
    );
    final tails = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_tailPositions, 0, count * _tailVertices * 2),
      colors: Int32List.sublistView(_tailColors, 0, count * _tailVertices),
    );
    // BlendMode.dst: use the vertex colors as they are.
    canvas.drawVertices(tails, BlendMode.dst, _tailPaint);
    tails.dispose();
  }

  void _setTriangle(int offset, double x0, double y0, double x1, double y1, double x2, double y2) {
    _tailPositions[offset] = x0;
    _tailPositions[offset + 1] = y0;
    _tailPositions[offset + 2] = x1;
    _tailPositions[offset + 3] = y1;
    _tailPositions[offset + 4] = x2;
    _tailPositions[offset + 5] = y2;
  }

  @override
  bool shouldRepaint(BatchedStarsPainter oldDelegate) =>
      oldDelegate.starfield != starfield || oldDelegate.sprite != sprite;
}
