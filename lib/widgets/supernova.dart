import 'dart:math';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:starfields/starfield/starfield.dart';

/// Timeline of the supernova that follows an explosion's burst: a white flash,
/// an expanding shockwave ring, and a blue afterglow that fades while the core
/// grows back. All functions take the seconds since the burst; constants are
/// meant for experimenting.
class Supernova {
  Supernova._();

  /// Flash: full white at the burst, exponential fade with this time constant.
  static const double flashFade = 0.14;

  /// Shockwave: time for the ring to expand past the screen corners.
  static const double shockwaveSeconds = 1.4;

  /// Afterglow: rises quickly, then fades out by the end of the comeback.
  static const double afterglowRise = 0.25;
  static const double afterglowPeak = 0.55;
  static const double afterglowSeconds = Starfield.burstPauseSeconds + Starfield.comebackRampSeconds;

  /// How long anything is visible.
  static const double seconds = afterglowSeconds;

  /// Opacity of the white flash.
  static double flash(double t) => t < 0 ? 0 : exp(-t / flashFade);

  /// Shockwave progress 0..1 (radius grows fast, then slows: ease-out).
  static double shockwave(double t) => t < 0 ? 0 : (t / shockwaveSeconds).clamp(0.0, 1.0);

  /// Opacity of the blue afterglow.
  static double afterglow(double t) {
    if (t < 0 || t >= afterglowSeconds) return 0;
    if (t < afterglowRise) return afterglowPeak * Curves.easeOut.transform(t / afterglowRise);
    final fade = (t - afterglowRise) / (afterglowSeconds - afterglowRise);
    return afterglowPeak * (1 - Curves.easeInOut.transform(fade));
  }
}

/// Paints the supernova with additive blending (light adds to light) over the
/// starfield, based on the starfield's latest explosion.
class SupernovaPainter extends CustomPainter {
  final Starfield starfield;
  final ValueListenable<double> time;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _paleBlue = Color(0xFFB4DCFF);
  static const Color _ringColor = Color(0xFFC8F0FF); // cyan-white
  static const Color _glowCore = Color(0xFF4FA8FF); // cyan-blue
  static const Color _glowColor = Color(0xFF2E5BFF); // deep blue

  final Paint _paint = Paint()..blendMode = BlendMode.plus;

  SupernovaPainter({required this.starfield, required this.time}) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final start = starfield.explosionStart;
    if (start == null) return;
    final t = time.value - start - Starfield.dropOffSeconds; // seconds since the burst
    if (t < 0 || t > Supernova.seconds) return;

    // Draw in the starfield's normalized space (-0.5..0.5 on both axes): the
    // stars spread stretched to the window's aspect ratio, so circles here
    // become ellipses on screen that match the burst.
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(size.width, size.height);
    const screen = Rect.fromLTRB(-0.5, -0.5, 0.5, 0.5);
    const reach = 0.8; // a bit past the corners (0.71)

    void fill(List<Color> colors, List<double> stops, double radius) {
      _paint.shader = RadialGradient(
        colors: colors,
        stops: stops,
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
      canvas.drawRect(screen, _paint);
    }

    // Afterglow: a blue nebula, brightest (and a bit cyan) in the middle.
    final glow = Supernova.afterglow(t);
    if (glow > 0) {
      fill(
        [
          _glowCore.withValues(alpha: glow),
          _glowColor.withValues(alpha: glow * 0.6),
          _glowColor.withValues(alpha: glow * 0.2),
          _glowColor.withAlpha(0),
        ],
        const [0.0, 0.35, 0.7, 1.0],
        reach,
      );
    }

    // Shockwave: a soft glowing band that widens and fades as it expands.
    final p = Supernova.shockwave(t);
    if (p < 1) {
      final radius = reach * Curves.easeOutCubic.transform(p);
      final width = 0.01 + 0.12 * p;
      final intensity = pow(1 - p, 1.5).toDouble();
      final outer = radius + width * 0.5;
      double at(double r) => (r / outer).clamp(0.0, 1.0);
      fill(
        [
          _ringColor.withAlpha(0),
          _ringColor.withValues(alpha: intensity * 0.35),
          _ringColor.withValues(alpha: intensity),
          _ringColor.withValues(alpha: intensity * 0.3),
          _ringColor.withAlpha(0),
        ],
        [at(radius - width), at(radius - width / 2), at(radius), at(radius + width / 4), 1.0],
        outer,
      );
    }

    // Flash: blinding at the core, softer and bluish towards the edges.
    final flash = Supernova.flash(t);
    if (flash > 0.01) {
      fill(
        [
          _white.withValues(alpha: flash),
          _white.withValues(alpha: flash * 0.85),
          _paleBlue.withValues(alpha: flash * 0.35),
        ],
        const [0.0, 0.3, 1.0],
        reach,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SupernovaPainter oldDelegate) => oldDelegate.starfield != starfield;
}
