import Foundation

/// Swift port of `HyperspaceDrive` and the uniform constants of
/// `HyperspacePainter` (lib/renderers/hyperspace_painter.dart). Keep in step.
///
/// Speed and streak stretch ease exponentially from the current state towards
/// the target, so changing course mid-transition stays smooth; the distance
/// travelled is the integral of the speed, in closed form.
final class HyperspaceDrive {
  static let jumpSpeed = 5.0
  static let jumpStretch = 2.6
  private static let jumpEase = 0.5  // seconds
  private static let dropOutEase = 0.9  // slower: a gentle deceleration

  // Must match the shader (Hyperspace.metal / hyperspace.frag).
  static let layers = 4.0
  static let columns = 1024.0
  static let row = 0.35
  static let rowPeriod = 4096.0
  private static let visibleRho = 4.8  // rows from the fade-in to the edge

  /// Cells that can hold a streak, over all layers.
  static let cells = layers * columns * visibleRho / row

  /// Per layer: outward speed in rho per second (far layers slower).
  static let layerSpeeds = [0.55, 0.8, 1.15, 1.6]

  /// Streak length in rho per unit of speed.
  static let lengthPerSpeed = 0.13

  private var since = 0.0  // time of the last change
  private var travel0 = 0.0  // travel at that time
  private var speed0 = 1.0
  private var stretch0 = 1.0
  private var targetSpeed = 1.0
  private var targetStretch = 1.0
  private var ease = jumpEase

  var jumping: Bool { targetSpeed > 1 }

  private func decay(_ time: Double) -> Double { exp(-max(0, time - since) / ease) }

  /// Speed (cruise = 1) at `time`.
  func speed(_ time: Double) -> Double { targetSpeed + (speed0 - targetSpeed) * decay(time) }

  /// Streak length factor at `time`.
  func stretch(_ time: Double) -> Double { targetStretch + (stretch0 - targetStretch) * decay(time) }

  /// Distance travelled up to `time`, in cruise-seconds.
  func travel(_ time: Double) -> Double {
    let age = max(0, time - since)
    return travel0 + targetSpeed * age + (speed0 - targetSpeed) * ease * (1 - decay(time))
  }

  /// Jumps to light speed (or drops out of it) from `time` on.
  func engage(jump: Bool, time: Double) {
    guard jump != jumping else { return }
    travel0 = travel(time)
    speed0 = speed(time)
    stretch0 = stretch(time)
    since = time
    targetSpeed = jump ? Self.jumpSpeed : 1
    targetStretch = jump ? Self.jumpStretch : 1
    ease = jump ? Self.jumpEase : Self.dropOutEase
  }
}
