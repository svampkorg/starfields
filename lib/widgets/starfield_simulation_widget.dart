import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:starfields/renderers/batched_stars_painter.dart';
import 'package:starfields/renderers/star_shaders.dart';
import 'package:starfields/renderers/styled_stars_painter.dart';
import 'package:starfields/starfield/starfield.dart';

/// How the stars are drawn.
enum StarfieldRenderer {
  /// One atlas draw for all glows and one vertices draw for all tails.
  batched('Batched'),

  /// Same simulation as [batched]; glows and tails are textured quads from a
  /// shader-generated atlas, in one draw call, with antialiased tails.
  styled('Styled'),

  /// Full-screen procedural shader on a log-polar grid (not implemented yet).
  procedural('Procedural'),

  /// Classic constant-cost hyperspace shader (not implemented yet).
  hyperspace('Hyperspace');

  const StarfieldRenderer(this.label);
  final String label;

  bool get isAvailable => this == batched || this == styled;
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
  final ui.Image _sprite = BatchedStarsPainter.createSprite();
  late Starfield _starfield;
  late CustomPainter _painter;

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
    } else {
      if (oldWidget.numberOfStars != widget.numberOfStars) {
        _starfield.resize(widget.numberOfStars, time: _now);
        _startTicker();
      }
      // A new renderer draws the same starfield: no reset.
      if (oldWidget.renderer != widget.renderer) _createPainter();
    }
  }

  void _createStarfield() {
    final starfield = Starfield(
      count: widget.numberOfStars,
      tickSeconds: widget.speed / 1000,
      respawn: !widget.explode,
      startTime: _now,
    );
    _starfield = starfield;
    _createPainter();
  }

  void _createPainter() {
    _painter = switch (widget.renderer) {
      StarfieldRenderer.batched => BatchedStarsPainter(starfield: _starfield, sprite: _sprite, repaint: _time),
      StarfieldRenderer.styled => StyledStarsPainter(
        starfield: _starfield,
        atlas: StarShaders.styledAtlas,
        repaint: _time,
      ),
      StarfieldRenderer.procedural || StarfieldRenderer.hyperspace => throw UnimplementedError(
        '${widget.renderer.label} renderer is not implemented yet',
      ),
    };
  }

  void _startTicker() {
    if (_ticker.isActive) return;
    _tickerStart = _now;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    _now = _tickerStart + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final starfield = _starfield;
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
        RepaintBoundary(child: CustomPaint(painter: _painter)),
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
