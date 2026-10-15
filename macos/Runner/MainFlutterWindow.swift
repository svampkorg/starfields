import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerWindowChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// "starfields/window": native full screen for the Dart side
  /// (lib/platform/app_window.dart).
  ///   Dart -> native: toggleFullScreen, isFullScreen
  ///   native -> Dart: fullScreenChanged(bool), also when the user leaves full
  ///                   screen with Esc, the green button or Mission Control.
  private func registerWindowChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "starfields/window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "toggleFullScreen":
        self.toggleFullScreen(nil)
        result(nil)
      case "isFullScreen":
        result(self.styleMask.contains(.fullScreen))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    windowChannel = channel

    for (name, fullScreen) in [
      (NSWindow.didEnterFullScreenNotification, true),
      (NSWindow.didExitFullScreenNotification, false),
    ] {
      NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
        self?.windowChannel?.invokeMethod("fullScreenChanged", arguments: fullScreen)
      }
    }
  }
}
