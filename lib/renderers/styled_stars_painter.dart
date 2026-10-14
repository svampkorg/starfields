import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:starfields/renderers/batched_stars_painter.dart';
import 'package:starfields/renderers/star_shaders.dart';
import 'package:starfields/starfield/starfield.dart';

/// Same simulation as [BatchedStarsPainter], drawn from a shader-generated
/// atlas ([StarShaders.styledAtlas]): every glow and tail is a textured quad,
/// all in one `drawVertices` call. Tails get antialiased edges from the atlas
/// strip of their width class.
class StyledStarsPainter extends CustomPainter {
  final Starfield starfield;
  final ui.Image atlas;

  /// Visible part of the glow radius (see [BatchedStarsPainter]).
  static const double _visibleGlow = 0.8;

  /// Extra width on each side of a tail for the antialiased edge; must match
  /// the 1 px edge in `shaders/styled_atlas.frag`.
  static const double _edge = 1;

  static const int _quadFloats = 12; // 6 vertices * (x, y)

  // Reusable buffers for glows followed by tails, grown with the starfield.
  Float32List _positions = Float32List(0);
  Float32List _coords = Float32List(0);
  late final Paint _paint = Paint()
    ..shader = ui.ImageShader(atlas, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage)
    ..filterQuality = FilterQuality.low;

  StyledStarsPainter({required this.starfield, required this.atlas, super.repaint}) {
    _ensureCapacity(starfield.count);
  }

  void _ensureCapacity(int stars) {
    final capacity = _coords.length ~/ (_quadFloats * 2);
    if (stars <= capacity) return;
    final newCapacity = max(stars, capacity * 2);
    _positions = Float32List(newCapacity * 2 * _quadFloats);
    _coords = Float32List(newCapacity * 2 * _quadFloats);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final count = starfield.visibleCount;
    if (count == 0) return;
    _ensureCapacity(count);
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const glow = StarShaders.glowSize + 0.0;
    const along0 = 0.5, along1 = StarShaders.atlasWidth - 0.5; // half-texel insets
    var tails = 0;

    for (var i = 0; i < count; i++) {
      final px = centerX + starfield.x[i] * size.width;
      final py = centerY + starfield.y[i] * size.height;
      final starSize = starfield.size[i];

      // Glow: a square around the visible disc, mapped onto the atlas disc.
      final r = starSize * 5 * _visibleGlow;
      _setQuad(_positions, i, px - r, py - r, px + r, py - r, px + r, py + r, px - r, py + r);
      _setQuad(_coords, i, 0, 0, glow, 0, glow, glow, 0, glow);

      // Tail: a strip from the star towards the center, 1 px wider on each
      // side, mapped onto the atlas strip of its width class. Sub-pixel tails
      // are skipped (LOD).
      var dx = centerX - px;
      var dy = centerY - py;
      final distance = sqrt(dx * dx + dy * dy);
      if (distance <= 0.5 || starSize < BatchedStarsPainter.minTailWidth) continue;
      dx /= distance;
      dy /= distance;
      final length = min(starSize * 10 + 20, distance);
      final band = ((starSize / 2) * 4).round().clamp(1, StarShaders.tailBands) - 1;
      final halfWidth = (band + 1) / 4; // the width class actually drawn
      final w = halfWidth + _edge;
      final nx = -dy * w, ny = dx * w;
      final endX = px + dx * length, endY = py + dy * length;
      final q = count + tails;
      _setQuad(_positions, q, px + nx, py + ny, endX + nx, endY + ny, endX - nx, endY - ny, px - nx, py - ny);
      final top = glow + band * StarShaders.tailBandHeight + 0.5;
      final bottom = top + StarShaders.tailBandHeight - 1;
      _setQuad(_coords, q, along0, top, along1, top, along1, bottom, along0, bottom);
      tails++;
    }

    // Glows come first in the buffers, so tails are drawn on top.
    final quads = count + tails;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_positions, 0, quads * _quadFloats),
      textureCoordinates: Float32List.sublistView(_coords, 0, quads * _quadFloats),
    );
    canvas.drawVertices(vertices, BlendMode.srcOver, _paint);
    vertices.dispose();
  }

  /// Writes quad [index] (corners a, b, c, d in order) as two triangles.
  static void _setQuad(
    Float32List list,
    int index,
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
    double dx,
    double dy,
  ) {
    final o = index * _quadFloats;
    list
      ..[o] = ax
      ..[o + 1] = ay
      ..[o + 2] = bx
      ..[o + 3] = by
      ..[o + 4] = cx
      ..[o + 5] = cy
      ..[o + 6] = ax
      ..[o + 7] = ay
      ..[o + 8] = cx
      ..[o + 9] = cy
      ..[o + 10] = dx
      ..[o + 11] = dy;
  }

  @override
  bool shouldRepaint(StyledStarsPainter oldDelegate) => oldDelegate.starfield != starfield;
}
