import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native window control (macOS only), over the "starfields/window" channel
/// implemented in macos/Runner/MainFlutterWindow.swift.
class AppWindow {
  AppWindow._();

  static const MethodChannel _channel = MethodChannel('starfields/window');

  /// Whether full screen can be toggled on this platform.
  static bool get supportsFullScreen => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Current full-screen state, kept in sync with the native window (also when
  /// the user leaves full screen with Esc or the green button).
  static final ValueNotifier<bool> fullScreen = ValueNotifier(false);

  static bool _listening = false;

  /// Starts listening for native full-screen changes and reads the current
  /// state.
  static Future<void> init() async {
    if (!supportsFullScreen || _listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fullScreenChanged') fullScreen.value = call.arguments as bool;
    });
    try {
      fullScreen.value = await _channel.invokeMethod<bool>('isFullScreen') ?? false;
    } on MissingPluginException {
      // Not running in the macOS runner (e.g. tests).
    }
  }

  /// Enters or leaves native full screen (with the system animation).
  static Future<void> toggleFullScreen() async {
    if (!supportsFullScreen) return;
    try {
      await _channel.invokeMethod<void>('toggleFullScreen');
    } on MissingPluginException {
      // Not running in the macOS runner (e.g. tests).
    }
  }
}
