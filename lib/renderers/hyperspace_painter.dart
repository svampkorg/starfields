import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:starfields/starfield/starfield.dart';

/// Classic light-speed streaks from one full-screen fragment shader
/// (`shaders/hyperspace.frag`), at full resolution. The cost per pixel is
/// constant: the star count only sets the chance that a grid cell holds a
/// streak. An explosion is a "jump": streaks stretch and speed up.
class HyperspacePainter extends CustomPainter {
  final Starfield starfield;
  final ui.FragmentShader shader;
  final ValueListenable<double> time;
  final Paint _paint = Paint();

  HyperspacePainter({required this.starfield, required this.shader, required this.time}) : super(repaint: time);

  // Must match the shader.
  static const int layers = 4;
  static const double _columns = 1024;
  static const double _row = 0.35;
  static const double _rowPeriod = 4096;
  static const double _visibleRho = 4.8; // rows from the fade-in to the edge

  /// Cells that can hold a streak, over all layers.
  static const double cells = layers * _columns * _visibleRho / _row;

  /// Per layer: outward speed in rho per second (far layers slower).
  static const List<double> _speed = [0.55, 0.8, 1.15, 1.6];

  /// Streak length in rho per unit of speed.
  static const double _lengthPerSpeed = 0.13;

  // Jump: speed rises to 1 + _jumpBoost and streaks stretch by up to
  // 1 + _jumpStretch, easing in with time constant _jumpEase.
  static const double _jumpBoost = 4;
  static const double _jumpStretch = 1.6;
  static const double _jumpEase = 0.5;

  /// Number of streaks drawn for the current star count.
  static int drawnStars(int count) => min(count, cells.floor());

  @override
  void paint(Canvas canvas, Size size) {
    final now = time.value;
    // Distance travelled in "cruise seconds". During a jump the speed eases
    // up to 1 + boost; its integral in closed form keeps it exact.
    var travel = now;
    var stretch = 1.0;
    if (!starfield.respawn) {
      final age = max(0.0, now - starfield.startTime);
      final ease = 1 - exp(-age / _jumpEase);
      travel = starfield.startTime + age + _jumpBoost * (age - _jumpEase * ease);
      stretch = 1 + _jumpStretch * ease;
    }

    var i = 0;
    shader
      ..setFloat(i++, size.width)
      ..setFloat(i++, size.height)
      ..setFloat(i++, min(1.0, starfield.count / cells));
    for (final speed in _speed) {
      // Computed in double and wrapped to whole hash periods, so 32-bit GPU
      // floats never see a large value.
      shader.setFloat(i++, (speed * travel) % (_row * _rowPeriod));
    }
    for (final speed in _speed) {
      shader.setFloat(i++, speed * _lengthPerSpeed * stretch);
    }
    _paint.shader = shader;
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(HyperspacePainter oldDelegate) => oldDelegate.starfield != starfield;
}
