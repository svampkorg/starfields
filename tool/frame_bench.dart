// Frame timing benchmark.
//
//   flutter run --profile -d macos -t tool/frame_bench.dart --dart-define=STARS=2000
//
// Waits until every star has been spawned, records FrameTimings for a while,
// prints a summary line and exits. With --dart-define=SHOT=name.png it also
// saves a snapshot of the last frame into the (sandboxed) app's temp dir.
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:starfields/widgets/scaling_gradient_widget.dart';
import 'package:starfields/widgets/starfield_simulation_widget.dart';

const int stars = int.fromEnvironment('STARS', defaultValue: 200);
const int measureSeconds = int.fromEnvironment('SECONDS', defaultValue: 8);
const String shotPath = String.fromEnvironment('SHOT');

final _boundaryKey = GlobalKey();

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: _boundaryKey,
        child: const Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [StarfieldSimulationWidget(numberOfStars: stars), ScalingGradientWidget()],
          ),
        ),
      ),
    ),
  );

  // Stars are spawned one per 8 ms simulation step; let them all appear first.
  final warmUp = Duration(milliseconds: stars * 8 + 2000);
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> t) => timings.addAll(t);

  Future<void>.delayed(warmUp, () {
    SchedulerBinding.instance.addTimingsCallback(collect);
    Future<void>.delayed(const Duration(seconds: measureSeconds), () async {
      SchedulerBinding.instance.removeTimingsCallback(collect);
      _report(timings);
      if (shotPath.isNotEmpty) await _snapshot(shotPath);
      exit(0);
    });
  });
}

void _report(List<FrameTiming> timings) {
  double ms(Duration d) => d.inMicroseconds / 1000;
  String stats(List<double> v) {
    v.sort();
    final avg = v.reduce((a, b) => a + b) / v.length;
    final p90 = v[(v.length * 0.9).floor().clamp(0, v.length - 1)];
    return 'avg ${avg.toStringAsFixed(2)} ms, p90 ${p90.toStringAsFixed(2)} ms';
  }

  final fps = timings.length / measureSeconds;
  // ignore: avoid_print
  print(
    'BENCH stars=$stars frames=${timings.length} fps=${fps.toStringAsFixed(1)} | '
    'build ${stats(timings.map((t) => ms(t.buildDuration)).toList())} | '
    'raster ${stats(timings.map((t) => ms(t.rasterDuration)).toList())}',
  );
}

Future<void> _snapshot(String name) async {
  final boundary = _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final png = await image.toByteData(format: ImageByteFormat.png);
  final file = File('${Directory.systemTemp.path}/$name');
  await file.writeAsBytes(png!.buffer.asUint8List());
  // ignore: avoid_print
  print('SHOT ${file.path}');
}
