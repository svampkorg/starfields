import Foundation
import ScreenSaver

/// Which shader draws the stars.
enum SaverRenderer: String, CaseIterable {
  /// Light-speed streaks with periodic jumps.
  case hyperspace
  /// The app's Procedural renderer: glowing stars growing out of the center.
  case procedural
  /// Hand-written Metal (WarpSpeed.metal): gas clouds and motion-blurred
  /// stars at warp speed.
  case warp

  var title: String {
    switch self {
    case .hyperspace: "Hyperspace"
    case .procedural: "Procedural"
    case .warp: "Warp speed"
    }
  }
}

/// The saver's options, edited in the configure sheet (ConfigureSheet.swift)
/// and stored with ScreenSaverDefaults under the bundle identifier. In
/// legacyScreenSaver that is a preferences file in the host's container,
/// shared by the System Settings preview and the running saver.
///
/// Environment variables override the stored values, for test_host runs:
/// STARFIELDS_RENDERER (hyperspace/procedural), STARFIELDS_JUMPS (0/1),
/// STARFIELDS_CRUISE_SECONDS, STARFIELDS_LIGHT_SECONDS, STARFIELDS_STARS.
struct SaverSettings: Equatable {
  var renderer = SaverRenderer.hyperspace
  var jumps = true  // Hyperspace and Warp speed
  var cruiseSeconds = 30.0  // between jumps
  var lightSeconds = 20.0  // at light speed, including the jump itself
  var stars = 2000.0

  static let cruiseRange = 10.0...120.0
  static let lightRange = 5.0...60.0
  /// Procedural is far heavier per pixel: above ~5000 stars three displays
  /// dropped below 60 fps.
  static func starsRange(for renderer: SaverRenderer) -> ClosedRange<Double> {
    renderer == .procedural ? 500.0...5000.0 : 500.0...8000.0
  }

  private enum Key {
    static let renderer = "renderer"
    static let jumps = "jumps"
    static let cruiseSeconds = "cruiseSeconds"
    static let lightSeconds = "lightSeconds"
    static let stars = "stars"
  }

  private static var defaults: ScreenSaverDefaults? {
    guard let identifier = Bundle(for: StarfieldsMetalSaverView.self).bundleIdentifier else { return nil }
    return ScreenSaverDefaults(forModuleWithName: identifier)
  }

  /// Stored settings, clamped to the ranges, with environment overrides.
  static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> SaverSettings {
    var settings = SaverSettings()
    if let defaults {
      if let name = defaults.string(forKey: Key.renderer), let renderer = SaverRenderer(rawValue: name) {
        settings.renderer = renderer
      }
      if defaults.object(forKey: Key.jumps) != nil { settings.jumps = defaults.bool(forKey: Key.jumps) }
      if defaults.object(forKey: Key.cruiseSeconds) != nil {
        settings.cruiseSeconds = defaults.double(forKey: Key.cruiseSeconds)
      }
      if defaults.object(forKey: Key.lightSeconds) != nil {
        settings.lightSeconds = defaults.double(forKey: Key.lightSeconds)
      }
      if defaults.object(forKey: Key.stars) != nil { settings.stars = defaults.double(forKey: Key.stars) }
    }
    settings.cruiseSeconds = settings.cruiseSeconds.clamped(to: cruiseRange)
    settings.lightSeconds = settings.lightSeconds.clamped(to: lightRange)
    settings.stars = settings.stars.clamped(to: starsRange(for: settings.renderer))

    // Test overrides: not clamped, so a test can use a 2 s cycle.
    if let name = environment["STARFIELDS_RENDERER"], let renderer = SaverRenderer(rawValue: name) {
      settings.renderer = renderer
    }
    if let jumps = environment["STARFIELDS_JUMPS"] { settings.jumps = jumps != "0" }
    if let value = environment["STARFIELDS_CRUISE_SECONDS"].flatMap(Double.init) { settings.cruiseSeconds = value }
    if let value = environment["STARFIELDS_LIGHT_SECONDS"].flatMap(Double.init) { settings.lightSeconds = value }
    if let value = environment["STARFIELDS_STARS"].flatMap(Double.init) { settings.stars = value }
    return settings
  }

  /// Stores the settings and flushes them, so the other host process (System
  /// Settings' preview vs. the running saver) sees them.
  func save() {
    guard let defaults = Self.defaults else { return }
    defaults.set(renderer.rawValue, forKey: Key.renderer)
    defaults.set(jumps, forKey: Key.jumps)
    defaults.set(cruiseSeconds, forKey: Key.cruiseSeconds)
    defaults.set(lightSeconds, forKey: Key.lightSeconds)
    defaults.set(stars, forKey: Key.stars)
    defaults.synchronize()
  }
}

extension Double {
  fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
