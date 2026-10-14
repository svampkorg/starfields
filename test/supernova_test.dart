import 'package:flutter_test/flutter_test.dart';
import 'package:starfields/widgets/supernova.dart';

void main() {
  test('flash: full white at the burst, mostly gone within half a second', () {
    expect(Supernova.flash(-0.1), 0);
    expect(Supernova.flash(0), 1);
    expect(Supernova.flash(0.5), lessThan(0.1));
  });

  test('shockwave expands once, in about 1.4 s', () {
    expect(Supernova.shockwave(0), 0);
    expect(Supernova.shockwave(0.7), closeTo(0.5, 1e-9));
    expect(Supernova.shockwave(5), 1);
  });

  test('afterglow rises right after the flash and fades out by the end', () {
    expect(Supernova.afterglow(0), 0);
    expect(Supernova.afterglow(Supernova.afterglowRise), closeTo(Supernova.afterglowPeak, 1e-9));
    expect(Supernova.afterglow(2), allOf(greaterThan(0.1), lessThan(Supernova.afterglowPeak)));
    expect(Supernova.afterglow(Supernova.afterglowSeconds), 0);
    // Never brighter than the peak, and fading monotonically after it.
    var previous = Supernova.afterglowPeak;
    for (var t = Supernova.afterglowRise; t < Supernova.afterglowSeconds; t += 0.05) {
      final glow = Supernova.afterglow(t);
      expect(glow, lessThanOrEqualTo(previous + 1e-12));
      previous = glow;
    }
  });

  test('shockwave: sharp front, long gradual trail towards the center', () {
    for (var p = 0.05; p < 1; p += 0.1) {
      final band = Supernova.shockwaveBand(p, 0.8);
      expect(band.trail, greaterThan(band.lead * 4), reason: 'at progress $p');
      expect(band.radius - band.trail, greaterThanOrEqualTo(0)); // never past the center
    }
    // The trail fades gradually: monotonic, quadratic.
    expect(Supernova.trailFade(0), 1);
    expect(Supernova.trailFade(0.5), closeTo(0.25, 1e-9));
    expect(Supernova.trailFade(1), 0);
  });
}
