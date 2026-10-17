import Foundation

/// Warp speed's lens flare: now and then one bright, warm, flickering star
/// with anamorphic streaks (thin horizontal and vertical lines through it)
/// emerges from the center and flies outward with the travel, like the
/// flare stars - a slow approach in cruise, a rush at warp. The streaks
/// follow the speed: full at warp, a faint hint in cruise (full streaks
/// were too loud there), so a flare dropping out of warp mid-flight fades
/// to the cruise look. One at a time, tracked here on the CPU and drawn analytically by WarpSpeed.metal from its
/// position: a hash-based star can't be found by its neighbours on the
/// screen, a single known one costs a few `exp` per pixel.
struct WarpLensFlare {
  /// What the shader draws this frame; `brightness` 0 = none.
  struct Frame {
    var position = SIMD2<Float>(0, 0)  // logical pixels, y down
    var direction = SIMD2<Float>(1, 0)  // outward, unit
    var rho: Float = 0  // ln(distance / shortest side)
    var size: Float = 0  // core radius, logical pixels
    var brightness: Float = 0
    var flicker: Float = 1  // ~0.7..1.3
    var streaks: Float = 1  // 1 at warp .. faint in cruise
  }

  private struct Flight {
    var angle: Double
    var startTravel: Double  // the travel when it emerged
    var speed: Double  // rho per unit of travel, like a flare layer
    var size: Double  // own size factor
    var phases: SIMD3<Double>  // of the flicker's three waves
  }

  private var flight: Flight?
  private var nextStart: Double?
  private var lastTime = 0.0
  private var generator = SystemRandomNumberGenerator()

  /// Seconds between one flare leaving the screen and the next emerging; STARFIELDS_LENS_SECONDS fixes it (tests).
  private static let pause: ClosedRange<Double> =
    ProcessInfo.processInfo.environment["STARFIELDS_LENS_SECONDS"].flatMap(Double.init).map { $0...$0 }
    ?? 7...20
  /// Where it emerges and where it is done (distance / shortest side): past
  /// the corners the streak has faded too.
  private static let startRho = log(0.02)

  /// `time` in seconds, `travel` in rho at layer speed 1, `speed` 0..1 of
  /// light speed, `size` the view in logical pixels.
  mutating func update(time: Double, travel: Double, speed: Double, size: SIMD2<Double>) -> Frame {
    // A restarted cycle: the clock and the travel start again.
    if time < lastTime || flight.map({ travel < $0.startTravel }) == true {
      flight = nil
      nextStart = nil
    }
    lastTime = time
    let start = nextStart ?? time + Double.random(in: Self.pause, using: &generator)
    nextStart = start
    if flight == nil, time >= start {
      flight = Flight(
        angle: Double.random(in: 0..<(2 * .pi), using: &generator), startTravel: travel,
        speed: Double.random(in: 0.7...1.1, using: &generator), size: Double.random(in: 0.8...1.3, using: &generator),
        phases: SIMD3((0..<3).map { _ in Double.random(in: 0..<(2 * .pi), using: &generator) }))
    }
    guard let flight else { return Frame() }

    let shortest = min(size.x, size.y)
    let rho = Self.startRho + flight.speed * (travel - flight.startTravel)
    let r = exp(rho)
    let halfDiagonal = 0.5 * (size.x * size.x + size.y * size.y).squareRoot() / shortest
    if r > halfDiagonal * 1.6 {
      self.flight = nil
      nextStart = time + Double.random(in: Self.pause, using: &generator)
      return Frame()
    }
    let direction = SIMD2(cos(flight.angle), sin(flight.angle))
    let position = size * 0.5 + direction * (r * shortest)
    // Emerging from the center like the other stars; grows as it comes closer.
    // Off the screen its streak can still cross it: fade out by the end.
    let grown = smoothstep(0.02, 0.3, r)
    let leaving = 1 - smoothstep(halfDiagonal, halfDiagonal * 1.6, r)
    // Flicker: three waves at unrelated rates (3-9 Hz) - irregular, no beat.
    let waves = SIMD3(3.1, 5.7, 9.3) * (2 * .pi * time) + flight.phases
    let flicker = 1 + 0.3 * (0.5 * sin(waves.x) + 0.3 * sin(waves.y) + 0.2 * sin(waves.z))
    return Frame(
      position: SIMD2<Float>(position), direction: SIMD2<Float>(direction), rho: Float(rho),
      size: Float((1.5 + r * 12) * flight.size * (0.3 + 0.7 * grown)), brightness: Float((0.25 + 0.75 * grown) * leaving),
      flicker: Float(flicker),
      // Cruise speed is 0.13 of light speed.
      streaks: Float(0.12 + 0.88 * smoothstep(0.2, 0.9, speed)))
  }
}

private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
  let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
  return t * t * (3 - 2 * t)
}
