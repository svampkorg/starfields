import Foundation

/// Warp speed's gas clouds travel through "biomes": each is three colors
/// picked at random from a palette of nebula hues (a base, a second, an
/// accent). On every jump a new biome is picked and the colors cross-fade
/// into it over the whole warp, slowly at first (hidden by the fast drift),
/// finishing as the stars slow down: the new place is a surprise when
/// dropping out, not something to watch arrive. Within a biome the colors
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

  private var generator = SaverRandom()
  private var biome: [Int]  // palette indices of the biome being arrived at
  /// The biome's backdrop: its seed (the distant nebula's layout and stars).
  private(set) var layout: Float = 0
  /// Counts the biomes picked: a new one needs its backdrop rendered.
  private(set) var generation = 0
  private var from: [SIMD3<Float>]  // colors when the fade began
  private var progress = 1.0  // 0 = `from` .. 1 = `biome`
  private var fadeSeconds = 1.0  // at light speed, for this jump's fade
  private var wasAtWarp = false
  private(set) var colorTime = 0.0

  /// The jump reaches light speed this long into "Light speed lasts"
  /// (JumpCycle: brake 0.4 s, creep 1.6 s).
  private static let jumpSeconds = 2.0
  /// After the drop-out begins, what is left of the fade takes this long.
  private static let dropOutSeconds = 1.0
  /// How much faster the color drift runs at light speed.
  private static let warpDrift = 30.0

  init() {
    biome = Self.pick(using: &generator, avoiding: [])
    from = biome.map { Self.palette[$0] }
    layout = Self.pickLayout(using: &generator)
  }

  private static func pickLayout(using generator: inout SaverRandom) -> Float {
    Float(generator.next() % 10_000) / 100
  }

  /// The biome's own colors, where the fade ends (for its backdrop).
  var targetColors: [SIMD3<Float>] { biome.map { Self.palette[$0] } }

  /// Three different palette colors, not the same set as `current`.
  private static func pick(using generator: inout SaverRandom, avoiding current: [Int]) -> [Int] {
    while true {
      let colors = Array(palette.indices.shuffled(using: &generator).prefix(3))
      if Set(colors) != Set(current) { return colors }
    }
  }

  /// The colors to draw now: `from` blending into the biome - ease-in
  /// (~16 % at half the warp), the bulk late.
  var colors: [SIMD3<Float>] {
    let p = progress * progress
    let t = Float(p * p * (3 - 2 * p))
    return zip(from, biome).map { start, index in start + (Self.palette[index] - start) * t }
  }

  /// `dt` in seconds, `speed` 0..1 of light speed, `lightSeconds` the jump's
  /// "Light speed lasts"; `drift` scales the drift's clock (tests
  /// fast-forward it).
  mutating func update(dt: Double, speed: Double, lightSeconds: Double, drift: Double) {
    let atWarp = speed >= 0.9
    if atWarp && !wasAtWarp {
      // A jump: head for a new biome from wherever the colors are now.
      from = colors
      biome = Self.pick(using: &generator, avoiding: biome)
      layout = Self.pickLayout(using: &generator)
      generation += 1
      progress = 0
      fadeSeconds = max(1, lightSeconds - Self.jumpSeconds)
    }
    wasAtWarp = atWarp
    // At warp: spread over the time until the drop-out; after it, the rest
    // finishes while the stars slow down.
    progress = min(1, progress + dt / (atWarp ? fadeSeconds : Self.dropOutSeconds))
    colorTime += dt * drift * (1 + Self.warpDrift * speed * speed)
  }
}

/// Random numbers for the saver's looks: the system's, or - with
/// STARFIELDS_SEED set (tests) - a fixed sequence (SplitMix64), so two runs
/// show the same sky for before/after comparisons.
struct SaverRandom: RandomNumberGenerator {
  static let testSeed = ProcessInfo.processInfo.environment["STARFIELDS_SEED"].flatMap(UInt64.init)
  private var state = SaverRandom.testSeed
  private var system = SystemRandomNumberGenerator()

  mutating func next() -> UInt64 {
    guard var z = state else { return system.next() }
    z &+= 0x9E37_79B9_7F4A_7C15
    state = z
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
