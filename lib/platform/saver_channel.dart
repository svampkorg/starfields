import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Diagnostics from the screen saver's engine to its native view
/// (macos_saver/StarfieldsSaverView.swift), which writes them to the unified
/// log: `log stream --predicate 'subsystem == "com.bosse.starfields.saver"'`.
class SaverChannel {
  SaverChannel._();

  static const MethodChannel _channel = MethodChannel('starfields/saver');

  /// Reports frame statistics every [interval]: frames per second and the
  /// average build and raster time, plus the time until the first frame.
  static void reportFrameStats({Duration interval = const Duration(seconds: 5)}) {
    final started = DateTime.now();
    var firstFrameReported = false;
    var windowStart = DateTime.now();
    var frames = 0;
    var buildMicros = 0;
    var rasterMicros = 0;

    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      final now = DateTime.now();
      if (!firstFrameReported) {
        firstFrameReported = true;
        _send('first frame after ${now.difference(started).inMilliseconds} ms');
      }
      for (final timing in timings) {
        frames++;
        buildMicros += timing.buildDuration.inMicroseconds;
        rasterMicros += timing.rasterDuration.inMicroseconds;
      }
      final elapsed = now.difference(windowStart);
      if (elapsed < interval) return;
      final fps = frames * Duration.microsecondsPerSecond / elapsed.inMicroseconds;
      _send(
        'fps ${fps.toStringAsFixed(1)}, '
        'build ${(buildMicros / frames / 1000).toStringAsFixed(2)} ms, '
        'raster ${(rasterMicros / frames / 1000).toStringAsFixed(2)} ms',
      );
      windowStart = now;
      frames = buildMicros = rasterMicros = 0;
    });
  }

  static void _send(String message) {
    _channel.invokeMethod<void>('log', message).catchError((Object _) {
      // Not running in the saver (no handler).
    });
  }
}
