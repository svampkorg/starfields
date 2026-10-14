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
}
