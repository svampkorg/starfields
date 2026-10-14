import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:starfields/starfield/starfield.dart';

/// How the stars are drawn.
enum StarfieldRenderer {
  /// One atlas draw for all glows and one vertices draw for all tails (Phase 1).
  batched('Batched'),

  /// Full-screen fragment shader (Phase 2, not implemented yet).
  shader('Shader');

  const StarfieldRenderer(this.label);
  final String label;

  bool get isAvailable => this == batched;
}

class StarfieldSimulationWidget extends StatefulWidget {
  final int numberOfStars;

  /// Duration in milliseconds of one step of the original stepped simulation.
  /// Higher is slower.
  final int speed;
  final bool explode;
  final StarfieldRenderer renderer;

  /// Called whenever the number of stars on screen changes.
  final ValueChanged<int>? onVisibleCountChanged;

  const StarfieldSimulationWidget({
    super.key,
    required this.numberOfStars,
    this.speed = 8,
    this.explode = false,
    this.renderer = StarfieldRenderer.batched,
    this.onVisibleCountChanged,
  }) : assert(numberOfStars >= 0);

  @override
  State<StarfieldSimulationWidget> createState() => _StarfieldSimulationWidgetState();
}

class _StarfieldSimulationWidgetState extends State<StarfieldSimulationWidget> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final ui.Image _sprite = StarsPainter.createSprite();
  late StarsPainter _painter;

  /// Simulation clock in seconds. Keeps counting across ticker restarts (the
  /// ticker stops once an explosion is over), so spawn times stay valid.
  double _now = 0;
  double _tickerStart = 0;
  int _reportedVisibleCount = -1;

  @override
  void initState() {
    super.initState();
    _createStarfield();
    _ticker = createTicker(_tick);
    _startTicker();
  }

  @override
  void didUpdateWidget(StarfieldSimulationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed || oldWidget.explode != widget.explode) {
      _createStarfield();
      _startTicker();
    } else if (oldWidget.numberOfStars != widget.numberOfStars) {
      _painter.starfield.resize(widget.numberOfStars, time: _now);
      _startTicker();
    }
  }

  void _createStarfield() {
    final starfield = Starfield(
      count: widget.numberOfStars,
      tickSeconds: widget.speed / 1000,
      respawn: !widget.explode,
      startTime: _now,
    );
    _painter = StarsPainter(starfield: starfield, sprite: _sprite, repaint: _time);
  }

  void _startTicker() {
    if (_ticker.isActive) return;
    _tickerStart = _now;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    _now = _tickerStart + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final starfield = _painter.starfield;
    starfield.update(_now);
    _time.value = _now;
    if (starfield.visibleCount != _reportedVisibleCount) {
      _reportedVisibleCount = starfield.visibleCount;
      widget.onVisibleCountChanged?.call(_reportedVisibleCount);
    }
    if (starfield.isFinished) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _sprite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: switch (widget.renderer) {
            StarfieldRenderer.batched => CustomPaint(painter: _painter),
            StarfieldRenderer.shader => throw UnimplementedError('Shader renderer arrives in Phase 2'),
          },
        ),
        if (widget.explode)
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutSine,
            tween: Tween<double>(begin: 1.0, end: 0.0),
            builder: (context, value, child) => DecoratedBox(
              decoration: BoxDecoration(
                backgroundBlendMode: BlendMode.hardLight,
                gradient: RadialGradient(
                  radius: value * 2.2,
                  colors: const [Colors.white, Colors.blue, Colors.transparent],
                  stops: const [0.02, 0.2, 1.0],
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            backgroundBlendMode: BlendMode.hue,
            gradient: RadialGradient(
              radius: 0.7,
              colors: [
                Colors.white,
                Colors.cyanAccent,
                Colors.lightBlue,
                Colors.blueAccent,
                Colors.deepPurple,
                Colors.deepPurple.withValues(alpha: 0.4),
              ],
              stops: const [0.00, 0.3, 0.5, 0.6, 0.8, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints all star glows with a single atlas draw and all tails with a single
/// vertices draw, writing straight into reusable typed buffers.
class StarsPainter extends CustomPainter {
  final Starfield starfield;
  final ui.Image sprite;

  /// Radius in pixels of the pre-rendered glow sprite.
  static const double spriteRadius = 128;

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

  StarsPainter({required this.starfield, required this.sprite, super.repaint}) {
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
      stops: [0.0, 0.2, 0.8],
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

      // Glow: radius starSize * 5, sprite centered on the star.
      final scale = starSize * 5 / spriteRadius;
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
      if (distance > 0.5) {
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
  bool shouldRepaint(StarsPainter oldDelegate) => oldDelegate.starfield != starfield || oldDelegate.sprite != sprite;
}
