import Foundation

/// Swift port of `ProceduralLayers` (lib/renderers/procedural_layers.dart):
/// per-layer uniforms for shaders/procedural_stars.frag, computed in double
/// precision. One layer per star speed (1..10). Keep in step with the Dart
/// version and with the `Starfield` constants below.
struct ProceduralLayers {
  static let layers = 10

  /// Must match kRowPeriod in the shader.
  private static let rowPeriod = 4096.0

  // From lib/starfield/starfield.dart.
  private static let speedFactor = 0.004
  private static let growthPerTick = [0.001, 0.003, 0.006, 0.016, 0.030, 0.050, 0.070, 0.090, 0.120, 0.150]
  private static let dropOffSeconds = 1.8
  /// The app's simulation step (StarfieldSimulationWidget.speed = 8 ms).
  static let tickSeconds = 0.008

  /// Average rho a star travels during one life in the original simulation.
  private static let lifeRho = 9.35
  // Cell size bounds (rho, and radians around the center).
  private static let minCell = 0.2
  private static let maxCell = 2.0
  /// Cells are this many times the largest glow footprint.
  private static let footprintMargin = 2.2
  /// Fraction of a star's life spent before it starts growing.
  private static let absorbedFraction = 0.59
  /// Width in rho of the band burst stars start in.
  private static let burstBand = 2.015

  /// Uniform values in shader order: per layer x, y, z, w.
  var layer = [SIMD4<Float>](repeating: .zero, count: layers)
  var motion = [SIMD4<Float>](repeating: .zero, count: layers)

  mutating func compute(count: Double, time: Double, width: Double, height: Double) {
    let minDim = max(1, min(width, height))
    let aspect = max(width, height) / minDim
    // Stars start growing 0.015 from the center (in normalized units).
    let growRadiusPx = 0.015 * minDim
    let perLayer = count / Double(Self.layers)

    for s in 0..<Self.layers {
      let speed = Double(s + 1)
      let k = log(1 + speed * Self.speedFactor) / Self.tickSeconds
      let growth = Self.growthPerTick[s] / Self.tickSeconds

      // Largest glow radius / distance ratio over a star's life.
      let tPeak = max(0, 1 / k - 0.1 / growth)
      let footprintPx = 4 * (0.1 + growth * tPeak) / (growRadiusPx * exp(k * tPeak))
      let cell = min(max(Self.footprintMargin * footprintPx * aspect, Self.minCell), Self.maxCell)
      let cells = max(3, (2 * Double.pi / cell).rounded(.down))

      let expected = perLayer / Self.lifeRho * cell / cells
      // Wrapped in Double so 32-bit GPU floats never see a large value.
      let shift = (k * time).truncatingRemainder(dividingBy: cell * Self.rowPeriod)
      let waiting = Self.absorbedFraction + min(1 - Self.absorbedFraction, k * Self.dropOffSeconds / Self.lifeRho)
      let burst = perLayer * waiting / Self.burstBand * cell / cells

      layer[s] = SIMD4(Float(cell), Float(cells), Float(shift), Float(expected))
      motion[s] = SIMD4(Float(k), Float(growth), Float(min(cell, footprintPx * aspect * 1.1)), Float(burst))
    }
  }
}
