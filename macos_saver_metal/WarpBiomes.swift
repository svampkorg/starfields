import Foundation

/// Warp speed's gas clouds travel through "biomes": each is three colors
/// picked at random from a palette of nebula hues (a base, a second, an
/// accent). On every jump a new biome is picked and the colors cross-fade
/// into it while at warp - arriving somewhere else. Within a biome the colors
/// drift slowly (WarpSpeed.metal: the hue field and the mood waves follow
/// `colorTime`); at warp that drift runs ~30x faster, colors racing past.
struct WarpBiomes {
  /// Hues seen in nebula photos, about as bright as the clouds' first colors
  /// (the clouds are dim behind the stars).
  static let palette: [SIMD3<Float>] = [
    SIMD3(0.09, 0.16, 0.42),  // blue
    SIMD3(0.05, 0.24, 0.44),  // azure
    SIMD3(0.04, 0.30, 0.30),  // teal
    SIMD3(0.28, 0.14, 0.42),  // violet
    SIMD3(0.42, 0.10, 0.32),  // magenta
    SIMD3(0.44, 0.06, 0.08),  // hydrogen red
    SIMD3(0.46, 0.20, 0.05),  // rust orange
    // Saturated: a dim yellow on black reads as olive (and an olive green
    // only added mud, so there is none).
    SIMD3(0.52, 0.34, 0.03),  // warm gold
  ]

  private var generator = SystemRandomNumberGenerator()
  private var biome: [Int]  // palette indices of the biome being arrived at
  private var from: [SIMD3<Float>]  // colors when the fade began
  private var progress = 1.0  // 0 = `from` .. 1 = `biome`
  private var wasAtWarp = false
  private(set) var colorTime = 0.0

  /// Light speed seconds for the cross-fade into a new biome.
  private static let arrivalSeconds = 8.0
  /// How much faster the color drift runs at light speed.
  private static let warpDrift = 30.0

  init() {
    biome = Self.pick(using: &generator, avoiding: [])
    from = biome.map { Self.palette[$0] }
  }

  /// Three different palette colors, not the same set as `current`.
  private static func pick(using generator: inout SystemRandomNumberGenerator, avoiding current: [Int]) -> [Int] {
    while true {
      let colors = Array(palette.indices.shuffled(using: &generator).prefix(3))
      if Set(colors) != Set(current) { return colors }
    }
  }

  /// The colors to draw now: `from` blending into the biome.
  var colors: [SIMD3<Float>] {
    let t = Float(progress * progress * (3 - 2 * progress))
    return zip(from, biome).map { start, index in start + (Self.palette[index] - start) * t }
  }

  /// `dt` in seconds, `speed` 0..1 of light speed; `drift` scales the
  /// drift's clock (tests fast-forward it).
  mutating func update(dt: Double, speed: Double, drift: Double) {
    let atWarp = speed >= 0.9
    if atWarp && !wasAtWarp {
      // A jump: head for a new biome from wherever the colors are now.
      from = colors
      biome = Self.pick(using: &generator, avoiding: biome)
      progress = 0
    }
    wasAtWarp = atWarp
    progress = min(1, progress + dt * speed / Self.arrivalSeconds)
    colorTime += dt * drift * (1 + Self.warpDrift * speed * speed)
  }
}
