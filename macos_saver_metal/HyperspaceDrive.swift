import Foundation

/// The screen saver's drive: speed, streak stretch, glow, width and brightness ease
/// exponentially from the current state towards a target, so changing course
/// mid-transition stays smooth; the distance travelled is the integral of the
/// speed, in closed form. Same idea as `HyperspaceDrive` in
/// lib/renderers/hyperspace_painter.dart, with more eased values.
final class HyperspaceDrive {
  /// Values eased towards a target. Speed 1 = the app's Hyperspace cruise.
  struct State {
    var speed: Double
    var stretch: Double  // streak length factor
    var glow: Double  // halo strength
    var width: Double  // streak core width factor
    var boost: Double  // streak brightness factor

    func with(speed: Double) -> State {
      var state = self
      state.speed = speed
      return state
    }

    func mixed(towards target: State, keep: Double) -> State {
      func mix(_ a: Double, _ b: Double) -> Double { b + (a - b) * keep }
      return State(
        speed: mix(speed, target.speed), stretch: mix(stretch, target.stretch), glow: mix(glow, target.glow),
        width: mix(width, target.width), boost: mix(boost, target.boost))
    }
  }

  // Must match the shader (hyperspace_streaks.glsl).
  static let layers = 4.0
  static let columns = 1024.0
  static let row = 0.35
  static let rowPeriod = 4096.0
  private static let visibleRho = 4.8  // rows from the fade-in to the edge

  /// Cells that can hold a streak, over all layers.
  static let cells = layers * columns * visibleRho / row

  /// Per layer: outward speed in rho per second (far layers slower).
  static let layerSpeeds = [0.55, 0.8, 1.15, 1.6]

  /// Streak length in rho per unit of layer speed, at stretch 1.
  static let lengthPerSpeed = 0.13

  private var since = 0.0  // time of the last change
  private var travel0 = 0.0  // travel at that time
  private var start: State
  private var target: State
  private var ease = 1.0  // seconds
  private var speedCurve = SpeedCurve.ease(1)

  /// How the speed gets from the start to the target.
  enum SpeedCurve {
    /// Exponential easing with this time constant (seconds): fast at first,
    /// then settling.
    case ease(Double)
    /// An exponential ramp over `seconds`: a slow creep that gets very steep
    /// at the end. With steepness k, the last 10 % of the time carries
    /// 1 - e^(-k/10) of the change (k = 7: half).
    case ramp(seconds: Double, steepness: Double)
  }

  init(_ state: State) {
    start = state
    target = state
  }

  private func keep(_ time: Double, _ ease: Double) -> Double { exp(-max(0, time - since) / ease) }

  func state(_ time: Double) -> State {
    var state = start.mixed(towards: target, keep: keep(time, ease))
    state.speed = speed(time)
    return state
  }

  private func speed(_ time: Double) -> Double {
    let age = max(0, time - since)
    switch speedCurve {
    case .ease(let tau):
      return target.speed + (start.speed - target.speed) * exp(-age / tau)
    case .ramp(let seconds, let k):
      let x = min(age, seconds) / seconds
      return start.speed + (target.speed - start.speed) * (exp(k * x) - 1) / (exp(k) - 1)
    }
  }

  /// Distance travelled up to `time`, in cruise-seconds: the integral of the
  /// speed, in closed form.
  func travel(_ time: Double) -> Double {
    let age = max(0, time - since)
    let v0 = start.speed
    let v1 = target.speed
    switch speedCurve {
    case .ease(let tau):
      return travel0 + v1 * age + (v0 - v1) * tau * (1 - exp(-age / tau))
    case .ramp(let seconds, let k):
      let t = min(age, seconds)
      let b = (v1 - v0) / (exp(k) - 1)
      let ramp = v0 * t + b * (seconds / k * (exp(k * t / seconds) - 1) - t)
      return travel0 + ramp + v1 * max(0, age - seconds)
    }
  }

  /// Heads for `target` from `time` on: the look eases with time constant
  /// `ease`, the speed along `speedCurve` (by default the same easing).
  func engage(_ target: State, ease: Double, speedCurve: SpeedCurve? = nil, time: Double) {
    travel0 = travel(time)
    start = state(time)
    since = time
    self.target = target
    self.ease = ease
    self.speedCurve = speedCurve ?? .ease(ease)
  }
}

/// The light-speed cycle: a slow cruise with short tails; on a jump the stars
/// brake to a near halt and stretch out along their travel vector, then the
/// speed creeps up exponentially - very slowly, then suddenly - into light
/// speed, the stars staying stretched; dropping out shrinks them back.
final class JumpCycle {
  static let cruise = HyperspaceDrive.State(speed: 0.28, stretch: 0.2, glow: 0.5, width: 1.6, boost: 2.2)
  /// Nearly halted while the streaks grow: the growing streaks carry the
  /// shift, and the sudden end of the creep feels bigger.
  static let stretchOut = HyperspaceDrive.State(speed: 0.03, stretch: 5.0, glow: 1.3, width: 2.4, boost: 1.8)
  static let lightSpeed = stretchOut.with(speed: 2.2)

  private struct Phase {
    let target: HyperspaceDrive.State
    let ease: Double  // time constant towards the target
    var speedCurve: HyperspaceDrive.SpeedCurve? = nil  // for the speed, if not the same easing
    let seconds: Double  // until the next phase
  }

  private let phases: [Phase]
  private var index = 0
  private var phaseEnd: Double
  let drive = HyperspaceDrive(cruise)

  /// Timing from the saver's settings; without jumps it cruises forever.
  init(settings: SaverSettings) {
    let cruiseSeconds = settings.jumps ? settings.cruiseSeconds : .infinity
    let lightSeconds = settings.lightSeconds
    let brakeSeconds = 0.4
    let creepSeconds = 1.6
    phases = [
      Phase(target: Self.cruise, ease: 0.7, seconds: cruiseSeconds),  // dropping out: tails shrink
      // The jump: brake hard while the stars start to stretch out ...
      Phase(target: Self.stretchOut, ease: 0.45, speedCurve: .ease(0.12), seconds: brakeSeconds),
      // ... then creep up exponentially into light speed; the look keeps easing.
      Phase(
        target: Self.lightSpeed, ease: 0.45, speedCurve: .ramp(seconds: creepSeconds, steepness: 7),
        seconds: max(0, lightSeconds - brakeSeconds)),
    ]
    phaseEnd = cruiseSeconds
  }

  /// Advances to the phase that `time` (seconds since start) is in.
  func update(_ time: Double) {
    while time >= phaseEnd {
      index = (index + 1) % phases.count
      let phase = phases[index]
      drive.engage(phase.target, ease: phase.ease, speedCurve: phase.speedCurve, time: phaseEnd)
      phaseEnd += phase.seconds
    }
  }
}
