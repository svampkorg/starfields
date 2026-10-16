// Stand-in for legacyScreenSaver, for testing a .saver without System
// Settings: loads the bundle, puts one view per display in a borderless
// full-screen window (or one small titled window with --window), starts the
// animation, stops after the given seconds and exits. Same process model as
// the real host (several views in one process, Bundle.main is not the
// saver's), but a normal app: views get a window and a screen.
//
//   tool/build_saver.sh                    # also builds build/saver/test_host
//   build/saver/test_host build/saver/Starfields.saver 10
//   build/saver/test_host build/saver/Starfields.saver 10 --window
//
// Logs: log show --last 1m --predicate 'subsystem == "com.bosse.starfields.saver"'
import AppKit
import ScreenSaver

let arguments = CommandLine.arguments
guard arguments.count >= 3, let seconds = Double(arguments[2]) else {
  print("usage: test_host <path.saver> <seconds> [--window]")
  exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
guard let bundle = Bundle(path: arguments[1]), bundle.load(),
  let viewClass = bundle.principalClass as? ScreenSaverView.Type
else {
  print("test_host: could not load \(arguments[1])")
  exit(1)
}

let frames =
  arguments.contains("--window")
  ? [NSRect(x: 100, y: 100, width: 800, height: 500)] : NSScreen.screens.map(\.frame)
var windows: [NSWindow] = []
var views: [ScreenSaverView] = []
for frame in frames {
  let style: NSWindow.StyleMask = arguments.contains("--window") ? [.titled] : [.borderless]
  let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
  window.setFrame(frame, display: false)
  let view = viewClass.init(frame: NSRect(origin: .zero, size: frame.size), isPreview: false)!
  window.contentView = view
  window.orderFront(nil)
  windows.append(window)
  views.append(view)
}
views.forEach { $0.startAnimation() }
print("test_host: \(views.count) view(s) started")
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
  views.forEach { $0.stopAnimation() }
  print("test_host: stopped")
  // Let the engine finish shutting down before exiting.
  DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
}
app.run()
