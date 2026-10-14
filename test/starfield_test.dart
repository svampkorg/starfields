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

  group('explosion', () {
    int within(Starfield f, double distance) {
      var n = 0;
      for (var i = 0; i < f.visibleCount; i++) {
        if (max(f.x[i].abs(), f.y[i].abs()) < distance) n++;
      }
      return n;
    }

    Starfield steadyField() {
      final field = Starfield(count: 2000, random: Random(21));
      for (var t = 0.0; t <= 30; t += 1 / 60) {
        field.update(t);
      }
      return field;
    }

    test('absorbs the stars near the center and stops spawning', () {
      final field = steadyField();
      expect(within(field, 0.015), greaterThan(500)); // most stars live near the center
      field
        ..explode(30)
        ..update(30);
      expect(within(field, 0.015), 0);

      var previous = field.visibleCount;
      for (var t = 30.0; t < 30 + Starfield.dropOffSeconds; t += 1 / 60) {
        field.update(t);
        expect(within(field, 0.015), 0, reason: 'no new stars at ${t.toStringAsFixed(2)} s');
        expect(field.visibleCount, lessThanOrEqualTo(previous));
        previous = field.visibleCount;
      }
      expect(previous, lessThan(1000)); // the field has thinned out
    });

    test('bursts every waiting star out of the core at once', () {
      final field = steadyField()..explode(30);
      for (var t = 30.0; t < 30 + Starfield.dropOffSeconds; t += 1 / 60) {
        field.update(t);
      }
      final before = field.visibleCount;
      field.update(30 + Starfield.dropOffSeconds);
      expect(field.visibleCount, 2000); // every star is flying again
      expect(within(field, 0.031), greaterThanOrEqualTo(2000 - before)); // all at the core
    });

    test('stars come back gradually after the burst, without a second wave', () {
      // Newly born stars sit very close to the center. In a steady field their
      // number is about constant; after the burst it must build up gradually
      // and not overshoot (an overshoot is a second wave of stars).
      final reference = steadyField();
      final steadyLevel = within(reference, 0.002);

      final field = steadyField()..explode(30);
      final burst = 30 + Starfield.dropOffSeconds;
      var highest = 0;
      for (var t = 30.0; t < burst + 12; t += 1 / 60) {
        field.update(t);
        if (t > burst) highest = max(highest, within(field, 0.002));
        if ((t - burst - 0.5).abs() < 1 / 120) {
          expect(within(field, 0.002), lessThan(steadyLevel * 0.25), reason: 'gradual start');
        }
      }
      expect(highest, lessThan(steadyLevel * 1.2), reason: 'steady level $steadyLevel');
    });

    test('settles back into a steady starfield', () {
      double outside(Starfield f) => 1 - within(f, 0.05) / f.visibleCount;
      final reference = steadyField();
      for (var t = 30.0; t <= 90; t += 1 / 60) {
        reference.update(t);
      }
      final field = steadyField()..explode(30);
      for (var t = 30.0; t <= 90; t += 1 / 60) {
        field.update(t);
      }
      expect(field.visibleCount, 2000);
      expect(outside(field), closeTo(outside(reference), 0.1));
    });
  });

  test('resuming after a pause does not synchronise the stars', () {
    // Fraction of stars that are out of the center region: about constant in a
    // steady starfield. A synchronised respawn would put them all back at the
    // center at once, and they would then move out together as a wave.
    double outside(Starfield f) {
      var n = 0;
      for (var i = 0; i < f.visibleCount; i++) {
        if (max(f.x[i].abs(), f.y[i].abs()) > 0.05) n++;
      }
      return n / f.visibleCount;
    }

    final steady = Starfield(count: 2000, random: Random(11));
    for (var t = 0.0; t <= 60; t += 1 / 60) {
      steady.update(t);
    }
    final expected = outside(steady);

    final paused = Starfield(count: 2000, random: Random(11));
    for (var t = 0.0; t <= 20; t += 1 / 60) {
      paused.update(t);
    }
    for (var t = 60.0; t <= 61; t += 1 / 60) {
      paused.update(t); // resume after 40 s
      expect(outside(paused), closeTo(expected, 0.08), reason: 'at ${t.toStringAsFixed(2)} s');
    }
  });

  test('catches up after a long pause without replaying every life', () {
    final field = Starfield(count: 100, random: Random(4))..update(1);
    field.update(1e7);
    expect(field.visibleCount, 100);
  });

  group('resize', () {
    List<double> snapshot(Starfield f) => [
      for (var i = 0; i < f.visibleCount; i++) ...[f.x[i], f.y[i], f.size[i]],
    ];

    test('growing keeps existing stars and adds the new ones at once', () {
      final field = Starfield(count: 100, random: Random(5))..update(5);
      final before = snapshot(field);
      field
        ..resize(1000, time: 5)
        ..update(5);
      expect(field.count, 1000);
      expect(field.visibleCount, 1000);
      expect(snapshot(field).sublist(0, before.length), before);
    });

    test('shrinking keeps the first stars', () {
      final field = Starfield(count: 300, random: Random(6))..update(5);
      final before = snapshot(field);
      field
        ..resize(50, time: 5)
        ..update(5);
      expect(field.visibleCount, 50);
      expect(snapshot(field), before.sublist(0, 50 * 3));
    });

    test('added stars move and respawn like the others', () {
      final field = Starfield(count: 10, random: Random(8))..update(1);
      field.resize(20, time: 1);
      for (var t = 1.0; t < 60; t += 1 / 30) {
        field.update(t);
        expect(field.visibleCount, 20);
      }
    });
  });
}
