import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:starfields/renderers/procedural_layers.dart';

void main() {
  const size = Size(2014, 1245);

  ProceduralLayers compute(int count, {double age = 10, bool explode = false, Size screen = size}) =>
      ProceduralLayers()..compute(count: count, tickSeconds: 0.008, explode: explode, age: age, size: screen);

  test('cells are at least twice the glow reach, so only one neighbour can be reached', () {
    for (final screen in [size, const Size(400, 800), const Size(3840, 2160)]) {
      final layers = compute(200, screen: screen);
      for (var s = 0; s < ProceduralLayers.layers; s++) {
        final cell = layers.layer[s * 4];
        final cells = layers.layer[s * 4 + 1];
        final reach = layers.motion[s * 4 + 2];
        expect(cell, inInclusiveRange(0.2, 2.0));
        expect(cells, greaterThanOrEqualTo(3));
        // Angular cell is never narrower than the rho cell.
        expect(2 * pi / cells, greaterThanOrEqualTo(cell - 1e-9));
        if (cell < 2.0) expect(reach, lessThanOrEqualTo(cell / 2 + 1e-9), reason: 'layer $s on $screen');
      }
    }
  });

  test('draws every star at low counts and caps dense cells at high counts', () {
    expect(compute(200).effectiveStars, closeTo(200, 1e-6));
    // At 2000 the fastest layer already exceeds 4 stars per cell on this
    // screen, so a few of its stars are not drawn.
    expect(compute(2000).effectiveStars, inInclusiveRange(1900, 2000));
    final dense = compute(50000).effectiveStars;
    expect(dense, lessThan(50000));
    expect(dense, greaterThan(compute(20000).effectiveStars));
  });

  test('more stars only raise the per-cell density, existing stars stay', () {
    final few = compute(200), many = compute(2000);
    for (var s = 0; s < ProceduralLayers.layers; s++) {
      expect(many.layer[s * 4], few.layer[s * 4]); // same cells
      expect(many.layer[s * 4 + 2], few.layer[s * 4 + 2]); // same scroll
      expect(many.layer[s * 4 + 3], closeTo(few.layer[s * 4 + 3] * 10, 1e-9));
    }
  });

  test('steady scroll offset wraps after a whole number of hash periods', () {
    for (final age in [1.0, 1e3, 1e6]) {
      final layers = compute(200, age: age);
      for (var s = 0; s < ProceduralLayers.layers; s++) {
        expect(layers.layer[s * 4 + 2], lessThan(layers.layer[s * 4] * ProceduralLayers.rowPeriod));
      }
    }
  });
}
