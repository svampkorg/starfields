import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starfields/starfield/starfield.dart';

const tick = 0.008;

void main() {
  test('matches the original stepped simulation', () {
    for (var seed = 0; seed < 20; seed++) {
      final field = Starfield(count: 1, random: Random(seed))..update(0);
      var dx = field.x[0], dy = field.y[0];
      // Recover the star's speed from one step: offset *= 1 + speed * 0.004.
      field.update(tick);
      final speed = ((field.x[0] / dx - 1) / 0.004).round();
      expect(speed, inInclusiveRange(1, 10));
      const growth = [0.001, 0.003, 0.006, 0.016, 0.030, 0.050, 0.070, 0.090, 0.120, 0.150];

      // Port of the original Star.move() until the star leaves the screen.
      var size = Starfield.initialSize;
      for (var n = 1; dx.abs() <= 0.7 && dy.abs() <= 0.7; n++) {
        dx *= 1 + speed * 0.004;
        dy *= 1 + speed * 0.004;
        if (dx.abs() > 0.015 || dy.abs() > 0.015) size += growth[speed - 1];
        if (dx.abs() > 0.7 || dy.abs() > 0.7) break;

        field.update(n * tick);
        expect(field.x[0], closeTo(dx, 1e-9), reason: 'seed $seed step $n');
        expect(field.y[0], closeTo(dy, 1e-9), reason: 'seed $seed step $n');
        // Continuous growth vs. per-step growth differ by at most one step.
        expect(field.size[0], closeTo(size, growth[speed - 1] + 1e-9), reason: 'seed $seed step $n');
      }
    }
  });

  test('is independent of the frame rate', () {
    final direct = Starfield(count: 1, random: Random(7));
    final at60 = Starfield(count: 1, random: Random(7));
    final at144 = Starfield(count: 1, random: Random(7));
    for (var second = 1; second <= 60; second++) {
      for (var f = 1; f <= 60; f++) {
        at60.update(second - 1 + f / 60);
      }
      for (var f = 1; f <= 144; f++) {
        at144.update(second - 1 + f / 144);
      }
      direct.update(second.toDouble());
      for (final other in [at60, at144]) {
        expect(other.x[0], closeTo(direct.x[0], 1e-9), reason: 'at ${second}s');
        expect(other.y[0], closeTo(direct.y[0], 1e-9), reason: 'at ${second}s');
        expect(other.size[0], closeTo(direct.size[0], 1e-9), reason: 'at ${second}s');
      }
    }
  });

  test('adds one star per tick and keeps every star on screen', () {
    final field = Starfield(count: 200, random: Random(1));
    field.update(0);
    expect(field.visibleCount, 1);
    field.update(9.5 * tick);
    expect(field.visibleCount, 10);

    for (var t = 2.0; t < 120; t += 1 / 30) {
      field.update(t);
      expect(field.visibleCount, 200);
      for (var i = 0; i < field.visibleCount; i++) {
        expect(field.x[i].abs(), lessThanOrEqualTo(0.7));
        expect(field.y[i].abs(), lessThanOrEqualTo(0.7));
        expect(field.size[i], greaterThanOrEqualTo(Starfield.initialSize));
      }
    }
  });

  test('respawned stars start at the center', () {
    final field = Starfield(count: 1, random: Random(3));
    // Find a time just after the first respawn: offset collapses towards 0.
    var previous = 0.0;
    for (var t = 0.0; t < 60; t += 0.001) {
      field.update(t);
      final distance = max(field.x[0].abs(), field.y[0].abs());
      if (distance < previous) {
        expect(distance, lessThan(0.001));
        expect(field.size[0], Starfield.initialSize);
        return;
      }
      previous = distance;
    }
    fail('star never respawned');
  });

  test('explode spawns every star at once and never respawns', () {
    final field = Starfield(count: 50, respawn: false, random: Random(2))..update(0);
    expect(field.visibleCount, 50);
    expect(field.isFinished, isFalse);
    field.update(1e6);
    expect(field.visibleCount, 0);
    expect(field.isFinished, isTrue);
  });

  test('catches up after a long pause without replaying every life', () {
    final field = Starfield(count: 100, random: Random(4))..update(1);
    field.update(1e7);
    expect(field.visibleCount, 100);
  });
}
