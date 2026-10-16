import FlutterMacOS
import ScreenSaver
import os

private let log = Logger(subsystem: "com.bosse.starfields.saver", category: "saver")

/// macOS screen saver that hosts the Flutter app, running the
/// `screensaverMain` entry point from lib/main.dart.
///
/// The host (Apple's legacyScreenSaver) creates one view per display in a
/// single process. Only the view on the main display runs Flutter; the
/// others stay black. More than one Flutter render surface in the host broke
/// (spike, 2026-10-16): one engine per display hit a GPU hang within seconds,
/// one engine with a view per display stuttered and lost its blending. A
/// single engine renders at full refresh rate.
///
/// `Bundle.main` is the host's, not ours: the Dart project must point at the
/// App.framework inside this saver.
///
/// Built and installed by tool/build_saver.sh.
@objc(StarfieldsSaverView)
final class StarfieldsSaverView: ScreenSaverView {
  /// Whether a view in this host process already runs the engine.
  private static var engineRunning = false

  private var engine: FlutterEngine?
  private var flutterViewController: FlutterViewController?
  private var startedAt: CFTimeInterval = 0
  private var stopObserver: NSObjectProtocol?
  private var saverChannel: FlutterMethodChannel?

  override init?(frame: NSRect, isPreview: Bool) {
    super.init(frame: frame, isPreview: isPreview)
    log.notice("init frame=\(NSStringFromRect(frame), privacy: .public) preview=\(isPreview)")
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    // Flutter schedules its own frames (vsync); animateOneFrame is not needed.
    animationTimeInterval = 1
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  deinit {
    log.notice("deinit")
  }

  override func startAnimation() {
    super.startAnimation()
    log.notice("startAnimation screen=\(self.screenDescription, privacy: .public)")
    startFlutter()
  }

  override func stopAnimation() {
    log.notice("stopAnimation")
    stopFlutter()
    super.stopAnimation()
  }

  override func animateOneFrame() {}

  /// The host may start the animation before the view is in a window. Flutter
  /// binds its vsync to the window's display, so start only once there is one:
  /// started without it, the engine rendered unthrottled (263 fps on a 60 Hz
  /// display).
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    log.notice("viewDidMoveToWindow screen=\(self.screenDescription, privacy: .public)")
    if isAnimating { startFlutter() }
  }

  private var screenDescription: String {
    guard let screen = window?.screen else { return "none" }
    return "\(NSStringFromRect(screen.frame)) main=\(screen == NSScreen.screens.first)"
  }

  /// The preview, or the view on the main display (the one with the menu
  /// bar, `NSScreen.screens.first`).
  private var showsStarfield: Bool {
    isPreview || window?.screen == NSScreen.screens.first
  }

  private func startFlutter() {
    guard engine == nil else { return }
    guard window?.screen != nil else {
      log.notice("no window/screen yet; waiting")
      return
    }
    guard showsStarfield, !Self.engineRunning else {
      log.notice("not the main display; this view stays black")
      return
    }
    startedAt = CACurrentMediaTime()
    let saverBundle = Bundle(for: StarfieldsSaverView.self)
    guard
      let appFrameworkURL = saverBundle.privateFrameworksURL?.appendingPathComponent("App.framework"),
      let appBundle = Bundle(url: appFrameworkURL)
    else {
      log.error("App.framework not found in \(saverBundle.bundlePath, privacy: .public)")
      return
    }
    let project = FlutterDartProject(precompiledDartBundle: appBundle)
    // Otherwise the engine passes on the host process's arguments.
    project.dartEntrypointArguments = []
    let engine = FlutterEngine(name: "starfields-saver", project: project, allowHeadlessExecution: false)
    // Without headless execution the engine only runs with a view controller.
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    // lib/platform/saver_channel.dart: diagnostics from Dart into the unified log.
    let channel = FlutterMethodChannel(name: "starfields/saver", binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "log", let message = call.arguments as? String {
        log.notice("dart: \(message, privacy: .public)")
      }
      result(nil)
    }
    guard engine.run(withEntrypoint: "screensaverMain") else {
      log.error("engine.run failed")
      return
    }
    controller.backgroundColor = .black
    // The host dismisses the saver on input; Flutter must not track the mouse.
    controller.mouseTrackingMode = .none
    controller.view.frame = bounds
    controller.view.autoresizingMask = [.width, .height]
    addSubview(controller.view)
    self.engine = engine
    flutterViewController = controller
    saverChannel = channel
    Self.engineRunning = true
    log.notice(
      "engine started in \((CACurrentMediaTime() - self.startedAt) * 1000, format: .fixed(precision: 1)) ms, \(Int(self.bounds.width))x\(Int(self.bounds.height))"
    )

    // Known host quirk: legacyScreenSaver does not always call stopAnimation
    // (or unload the saver) after dismissal, which would leave the engine
    // running. Stop on the system's "will stop" notification as well.
    stopObserver = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("com.apple.screensaver.willstop"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      log.notice("willstop notification")
      self?.stopFlutter()
    }
  }

  private func stopFlutter() {
    if let stopObserver {
      DistributedNotificationCenter.default().removeObserver(stopObserver)
      self.stopObserver = nil
    }
    guard let engine else { return }
    log.notice("stopping engine after \(CACurrentMediaTime() - self.startedAt, format: .fixed(precision: 1)) s")
    saverChannel?.setMethodCallHandler(nil)
    saverChannel = nil
    flutterViewController?.view.removeFromSuperview()
    flutterViewController = nil
    engine.shutDownEngine()
    self.engine = nil
    Self.engineRunning = false
  }
}
