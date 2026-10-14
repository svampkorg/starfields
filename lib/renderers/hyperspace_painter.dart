import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:starfields/starfield/starfield.dart';

/// Speed and streak stretch of the hyperspace renderer. Jumping and dropping
/// out both ease exponentially from the current state towards the target, so
/// changing course mid-transition stays smooth. The distance travelled is the
/// integral of the speed, in closed form.
class HyperspaceDrive {
  /// Cruise speed is 1; a jump eases up to [jumpSpeed].
  static const double jumpSpeed = 5;
  static const double jumpStretch = 2.6;
  static const double _jumpEase = 0.5; // seconds
  static const double _dropOutEase = 0.9; // slower: a gentle deceleration

  double _since = 0; // time of the last change
  double _travel0 = 0; // travel at that time
  double _speed0 = 1;
  double _stretch0 = 1;
  double _targetSpeed = 1;
  double _targetStretch = 1;
  double _ease = _jumpEase;

  bool get jumping => _targetSpeed > 1;

  double _decay(double time) => exp(-max(0.0, time - _since) / _ease);

  /// Speed (cruise = 1) at [time].
  double speed(double time) => _targetSpeed + (_speed0 - _targetSpeed) * _decay(time);

  /// Streak length factor at [time].
  double stretch(double time) => _targetStretch + (_stretch0 - _targetStretch) * _decay(time);

  /// Distance travelled up to [time], in cruise-seconds.
  double travel(double time) {
    final age = max(0.0, time - _since);
    return _travel0 + _targetSpeed * age + (_speed0 - _targetSpeed) * _ease * (1 - _decay(time));
  }

  /// Jumps to light speed (or drops out of it) from [time] on.
  void engage({required bool jump, required double time}) {
    if (jump == jumping) return;
    _travel0 = travel(time);
    _speed0 = speed(time);
    _stretch0 = stretch(time);
    _since = time;
    _targetSpeed = jump ? jumpSpeed : 1;
    _targetStretch = jump ? jumpStretch : 1;
    _ease = jump ? _jumpEase : _dropOutEase;
  }
}

/// Classic light-speed streaks from one full-screen fragment shader
/// (`shaders/hyperspace.frag`), at full resolution. The cost per pixel is
/// constant: the star count only sets the chance that a grid cell holds a
/// streak. Motion comes from a [HyperspaceDrive].
class HyperspacePainter extends CustomPainter {
  final Starfield starfield;
  final HyperspaceDrive drive;
  final ui.FragmentShader shader;
  final ValueListenable<double> time;
  final Paint _paint = Paint();

  HyperspacePainter({required this.starfield, required this.drive, required this.shader, required this.time})
    : super(repaint: time);

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

  /// Number of streaks drawn for the current star count.
  static int drawnStars(int count) => min(count, cells.floor());

  @override
  void paint(Canvas canvas, Size size) {
    final now = time.value;
    final travel = drive.travel(now);
    final stretch = drive.stretch(now);

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
