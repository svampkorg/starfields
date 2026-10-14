import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:starfields/renderers/batched_stars_painter.dart';
import 'package:starfields/renderers/hyperspace_painter.dart';
import 'package:starfields/renderers/procedural_stars_painter.dart';
import 'package:starfields/renderers/star_shaders.dart';
import 'package:starfields/renderers/styled_stars_painter.dart';
import 'package:starfields/starfield/starfield.dart';
import 'package:starfields/widgets/scaling_gradient_widget.dart';

/// How the stars are drawn.
enum StarfieldRenderer {
  /// One atlas draw for all glows and one vertices draw for all tails.
  batched('Batched'),

  /// Same simulation as [batched]; glows and tails are textured quads from a
  /// shader-generated atlas, in one draw call, with antialiased tails.
  styled('Styled'),

  /// Full-screen procedural shader on a log-polar grid: no star data at all.
  procedural('Procedural'),

  /// Classic light-speed streaks; constant cost per pixel at any star count.
  /// Explode = jump: streaks stretch and speed up.
  hyperspace('Hyperspace');

  const StarfieldRenderer(this.label);
  final String label;

  /// Renderers that draw the CPU simulation's stars. The others compute
  /// everything in a shader, so the CPU simulation pauses while they are on.
  bool get usesSimulation => this == batched || this == styled;
}

class StarfieldSimulationWidget extends StatefulWidget {
  final int numberOfStars;

  /// Duration in milliseconds of one step of the original stepped simulation.
  /// Higher is slower.
  final int speed;

  /// Each increase starts an explosion: spawning stops, the core grows, then
  /// every absorbed star bursts out (renderers other than hyperspace).
  final int explosions;

  /// Hyperspace only: jump to light speed (true) or cruise (false).
  final bool jump;

  final StarfieldRenderer renderer;

  /// Called whenever the number of stars on screen changes.
  final ValueChanged<int>? onVisibleCountChanged;

  const StarfieldSimulationWidget({
    super.key,
    required this.numberOfStars,
    this.speed = 8,
    this.explosions = 0,
    this.jump = false,
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
  ui.FragmentShader? _shader;
  final HyperspaceDrive _drive = HyperspaceDrive();

  /// Simulation clock in seconds.
  double _now = 0;
  int _reportedVisibleCount = -1;
  bool _explosionShowing = false;

  @override
  void initState() {
    super.initState();
    _createStarfield();
    _drive.engage(jump: widget.jump, time: 0);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(StarfieldSimulationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _createStarfield();
    } else {
      if (oldWidget.numberOfStars != widget.numberOfStars) _starfield.resize(widget.numberOfStars, time: _now);
      // A new renderer draws the same starfield: no reset.
      if (oldWidget.renderer != widget.renderer) _createPainter();
    }
    if (widget.explosions > oldWidget.explosions) {
      _starfield.explode(_now);
      _explosionShowing = true;
    }
    if (oldWidget.jump != widget.jump) _drive.engage(jump: widget.jump, time: _now);
  }

  void _createStarfield() {
    final starfield = Starfield(count: widget.numberOfStars, tickSeconds: widget.speed / 1000, startTime: _now);
    _starfield = starfield;
    _createPainter();
  }

  void _createPainter() {
    _shader?.dispose();
    _shader = null;
    _painter = switch (widget.renderer) {
      StarfieldRenderer.batched => BatchedStarsPainter(starfield: _starfield, sprite: _sprite, repaint: _time),
      StarfieldRenderer.styled => StyledStarsPainter(
        starfield: _starfield,
        atlas: StarShaders.styledAtlas,
        repaint: _time,
      ),
      StarfieldRenderer.procedural => ProceduralStarsPainter(
        starfield: _starfield,
        shader: _shader = StarShaders.procedural.fragmentShader(),
        time: _time,
      ),
      StarfieldRenderer.hyperspace => HyperspacePainter(
        starfield: _starfield,
        drive: _drive,
        shader: _shader = StarShaders.hyperspace.fragmentShader(),
        time: _time,
      ),
    };
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final starfield = _starfield;
    _time.value = _now;
    final int visible;
    if (widget.renderer.usesSimulation) {
      starfield.update(_now);
      visible = starfield.visibleCount;
    } else {
      // Shader-only renderers: no CPU simulation; the stats show what the
      // shader draws.
      final painter = _painter;
      visible = painter is ProceduralStarsPainter
          ? painter.estimateStars().round()
          : HyperspacePainter.drawnStars(starfield.count);
    }
    if (visible != _reportedVisibleCount) {
      _reportedVisibleCount = visible;
      widget.onVisibleCountChanged?.call(visible);
    }
    if (_explosionShowing && _explosionAge(_now) > _explosionSeconds) {
      setState(() => _explosionShowing = false);
    }
  }

  /// Charge, burst, pause, regrowth: the whole visible sequence.
  static const double _explosionSeconds =
      Starfield.dropOffSeconds + Starfield.burstPauseSeconds + Starfield.comebackRampSeconds;

  double _explosionAge(double now) => now - (_starfield.explosionStart ?? now);

  /// The explosion's own core: grows while spawning has stopped, and is gone
  /// at the burst.
  Widget _explosionCore() {
    return ValueListenableBuilder<double>(
      valueListenable: _time,
      builder: (context, now, _) {
        final age = _explosionAge(now);
        if (age >= Starfield.dropOffSeconds) return const SizedBox.shrink();
        return DecoratedBox(
          decoration: BoxDecoration(
            backgroundBlendMode: BlendMode.hardLight,
            gradient: RadialGradient(
              radius: 0.9 * Curves.easeInQuad.transform(age / Starfield.dropOffSeconds),
              colors: const [Colors.white, Colors.blue, Colors.transparent],
              stops: const [0.02, 0.2, 1.0],
            ),
          ),
        );
      },
    );
  }

  /// The normal core: vanishes at the burst, stays away during the pause, and
  /// grows back while stars come back.
  Widget _regrowingCore() {
    return ValueListenableBuilder<double>(
      valueListenable: _time,
      builder: (context, now, _) {
        final age = _explosionAge(now);
        final regrow = age - Starfield.dropOffSeconds - Starfield.burstPauseSeconds;
        final double scale;
        if (age < Starfield.dropOffSeconds) {
          scale = 1;
        } else if (regrow < 0) {
          scale = 0;
        } else {
          scale = Curves.easeInOut.transform((regrow / Starfield.comebackRampSeconds).clamp(0.0, 1.0));
        }
        return ScalingGradientWidget(scale: scale);
      },
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _sprite.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: CustomPaint(painter: _painter)),
        if (_explosionShowing && widget.renderer != StarfieldRenderer.hyperspace) _explosionCore(),
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
        if (_explosionShowing && widget.renderer != StarfieldRenderer.hyperspace)
          _regrowingCore()
        else
          const ScalingGradientWidget(),
      ],
    );
  }
}
