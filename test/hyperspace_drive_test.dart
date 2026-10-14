import 'package:flutter_test/flutter_test.dart';
import 'package:starfields/renderers/hyperspace_painter.dart';

void main() {
  test('cruises at speed 1 until a jump', () {
    final drive = HyperspaceDrive();
    expect(drive.speed(10), 1);
    expect(drive.travel(10), closeTo(10, 1e-9));
  });

  test('jump eases up to jump speed and drop-out eases back, without jumps in position or speed', () {
    final drive = HyperspaceDrive()..engage(jump: true, time: 10);
    expect(drive.speed(10), closeTo(1, 1e-9));
    expect(drive.speed(20), closeTo(HyperspaceDrive.jumpSpeed, 1e-3));
    expect(drive.stretch(20), closeTo(HyperspaceDrive.jumpStretch, 1e-3));

    // Drop out half way through the acceleration.
    final t = 10.3, before = drive.travel(t), speedBefore = drive.speed(t);
    drive.engage(jump: false, time: t);
    expect(drive.travel(t), closeTo(before, 1e-9));
    expect(drive.speed(t), closeTo(speedBefore, 1e-9));
    expect(drive.speed(30), closeTo(1, 1e-6));
    expect(drive.stretch(30), closeTo(1, 1e-6));
  });

  test('travel is the integral of speed', () {
    // Evaluated forward in time, like the app: jump at 1 s, drop out at 2.5 s.
    final drive = HyperspaceDrive();
    var integral = 0.0;
    const dt = 1e-4;
    for (var t = 0.0; t < 6; t += dt) {
      if (t >= 1 && !drive.jumping && t < 2.5) drive.engage(jump: true, time: t);
      if (t >= 2.5 && drive.jumping) drive.engage(jump: false, time: t);
      integral += drive.speed(t + dt / 2) * dt;
    }
    expect(drive.travel(6), closeTo(integral, 1e-3));
  });
}
