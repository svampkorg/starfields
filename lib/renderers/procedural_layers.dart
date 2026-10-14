import 'dart:math';
import 'dart:ui';

import 'package:starfields/starfield/starfield.dart';

/// Per-layer parameters for `shaders/procedural_stars.frag`, computed on the
/// CPU in double precision. One layer per star speed (1..10).
///
/// In log-polar coordinates (angle, rho = ln distance) every star of a layer
/// moves outward at the same constant rate `k`, so a layer is a grid of cells
/// that scrolls. See the shader for the full picture.
class ProceduralLayers {
  static const int layers = 10;

  /// Must match kMaxPerCell in the shader.
  static const int maxPerCell = 4;

  /// Must match kRowPeriod in the shader.
  static const double rowPeriod = 4096;

  /// Average rho a star travels during one life in the original simulation:
  /// from ln(origin) (~ ln(1e-4) - 0.5) to ln(0.7).
  static const double lifeRho = 9.35;

  // Bounds for the cell size (in rho, and in radians around the center).
  // The lower bound keeps tails (which point inward) within two rows.
  static const double _minCell = 0.2;
  static const double _maxCell = 2.0;

  /// Margin: cells are this many times the largest glow footprint, so a glow
  /// never extends past the neighbouring cell.
  static const double _footprintMargin = 2.2;

  /// Uniform values, [layers] * 4 each, in shader order.
  final List<double> layer = List.filled(layers * 4, 0);
  final List<double> motion = List.filled(layers * 4, 0);

  /// Number of stars the shader actually draws (cells hold at most
  /// [maxPerCell]), for the stats panel.
  double effectiveStars = 0;

  /// Fraction of a star's life (in rho) spent before it starts growing; these
  /// stars are absorbed by an explosion.
  static const double _absorbedFraction = 0.59;

  /// Width in rho of the band burst stars start in (radius 0.004 .. 0.03).
  static const double _burstBand = 2.015;

  void compute({required int count, required double tickSeconds, required double time, required Size size}) {
    final minDim = max(1.0, min(size.width, size.height));
    final aspect = max(size.width, size.height) / minDim;
    // Stars start growing 0.015 from the center (in normalized units).
    final growRadiusPx = 0.015 * minDim;
    final perLayer = count / layers;
    effectiveStars = 0;

    for (var s = 0; s < layers; s++) {
      final speed = s + 1;
      final k = log(1 + speed * Starfield.speedFactor) / tickSeconds;
      final growth = Starfield.growthPerTick[s] / tickSeconds;

      // Largest glow radius / distance ratio over a star's life: radius
      // 4 * size, size = 0.1 + growth * t, distance = growRadius * e^(k t).
      final tPeak = max(0.0, 1 / k - 0.1 / growth);
      final footprintPx = 4 * (0.1 + growth * tPeak) / (growRadiusPx * exp(k * tPeak));
      final cell = (_footprintMargin * footprintPx * aspect).clamp(_minCell, _maxCell);
      final cells = max(3, (2 * pi / cell).floor());

      // Steady state: a layer holds perLayer stars spread evenly over lifeRho.
      final expected = perLayer / lifeRho * cell / cells;
      final shift = (k * time) % (cell * rowPeriod);
      // Burst: the absorbed stars plus those that left the screen during the
      // drop-off, all starting in the burst band.
      final waiting = _absorbedFraction + min(1 - _absorbedFraction, k * Starfield.dropOffSeconds / lifeRho);
      final burst = perLayer * waiting / _burstBand * cell / cells;

      layer
        ..[s * 4] = cell
        ..[s * 4 + 1] = cells.toDouble()
        ..[s * 4 + 2] = shift
        ..[s * 4 + 3] = expected;
      motion
        ..[s * 4] = k
        ..[s * 4 + 1] = growth
        ..[s * 4 + 2] = min(cell, footprintPx * aspect * 1.1)
        ..[s * 4 + 3] = burst;

      effectiveStars += perLayer * min(1.0, maxPerCell / expected);
    }
  }
}
