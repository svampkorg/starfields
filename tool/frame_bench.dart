// Frame timing benchmark.
//
//   flutter run --profile -d macos -t tool/frame_bench.dart --dart-define=STARS=2000
//
// Waits until every star has been spawned, records FrameTimings for a while,
// prints a summary line and exits. Options (--dart-define=NAME=value):
//   SECONDS=8          measuring time
//   INSTANT=true       spawn all stars at once (via resize) instead of one per
//                      8 ms like the original start-up; for large star counts
//   RENDERER=batched   a StarfieldRenderer name
//   SHOT=name.png      also save a snapshot of the last frame into the
//                      (sandboxed) app's temp dir
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:starfields/renderers/star_shaders.dart';
import 'package:starfields/widgets/scaling_gradient_widget.dart';
import 'package:starfields/widgets/starfield_simulation_widget.dart';

const int stars = int.fromEnvironment('STARS', defaultValue: 200);
const int measureSeconds = int.fromEnvironment('SECONDS', defaultValue: 8);
const String shotPath = String.fromEnvironment('SHOT');
const bool instant = bool.fromEnvironment('INSTANT');
final StarfieldRenderer renderer = StarfieldRenderer.values.byName(
  const String.fromEnvironment('RENDERER', defaultValue: 'batched'),
);

final _boundaryKey = GlobalKey();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StarShaders.load();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: _boundaryKey,
        child: const Scaffold(
          backgroundColor: Colors.black,
          body: Stack(fit: StackFit.expand, children: [_BenchStarfield(), ScalingGradientWidget()]),
        ),
      ),
    ),
  );

  // Stars are spawned one per 8 ms simulation step; let them all appear first.
  final warmUp = Duration(milliseconds: (instant ? 0 : stars * 8) + 2000);
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
    return 'avg ${avg.toStringAsFixed(2)} ms, p90 ${p90.toStringAsFixed(2)} ms, max ${v.last.toStringAsFixed(2)} ms';
  }

  final fps = timings.length / measureSeconds;
  // A frame misses a 120 Hz vsync when either thread needs more than 8.3 ms.
  final missed = timings.where((t) => ms(t.buildDuration) > 8.33 || ms(t.rasterDuration) > 8.33).length;
  // ignore: avoid_print
  print(
    'BENCH ${renderer.name} stars=$stars frames=${timings.length} fps=${fps.toStringAsFixed(1)} missed=$missed | '
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

/// Starts with one star and, with INSTANT, resizes to [stars] after the first
/// frame so every star appears at once.
class _BenchStarfield extends StatefulWidget {
  const _BenchStarfield();

  @override
  State<_BenchStarfield> createState() => _BenchStarfieldState();
}

class _BenchStarfieldState extends State<_BenchStarfield> {
  int _count = instant ? 1 : stars;

  @override
  void initState() {
    super.initState();
    if (instant) {
      WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _count = stars));
    }
  }

  @override
  Widget build(BuildContext context) => StarfieldSimulationWidget(numberOfStars: _count, renderer: renderer);
}
