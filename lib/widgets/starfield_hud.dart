import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:starfields/widgets/starfield_simulation_widget.dart';

/// Star counts selectable with the slider.
const List<int> starCountSteps = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000];

String formatCount(int value) => value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Shows frames per second, build and raster times (from the engine's
/// [FrameTiming]s, averaged over the last second) and the star count.
class FrameStatsPanel extends StatefulWidget {
  final ValueListenable<int> visibleStars;
  final int totalStars;

  const FrameStatsPanel({super.key, required this.visibleStars, required this.totalStars});

  @override
  State<FrameStatsPanel> createState() => _FrameStatsPanelState();
}

class _FrameStatsPanelState extends State<FrameStatsPanel> {
  static const _window = Duration(seconds: 1);
  static const _refreshInterval = Duration(milliseconds: 250);

  final Queue<FrameTiming> _timings = Queue();
  final Stopwatch _sinceRefresh = Stopwatch()..start();
  double? _fps;
  double _buildMs = 0;
  double _rasterMs = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  // Profile/release mode reports timings in batches about once a second,
  // debug mode after every frame; keep a sliding window of the last second.
  void _onTimings(List<FrameTiming> timings) {
    _timings.addAll(timings);
    int vsync(FrameTiming t) => t.timestampInMicroseconds(FramePhase.vsyncStart);
    final newest = vsync(_timings.last);
    while (newest - vsync(_timings.first) > _window.inMicroseconds) {
      _timings.removeFirst();
    }
    if (_sinceRefresh.elapsed < _refreshInterval || !mounted) return;
    _sinceRefresh.reset();

    final span = (newest - vsync(_timings.first)) / Duration.microsecondsPerSecond;
    double averageMs(Duration Function(FrameTiming) phase) =>
        _timings.fold(0, (sum, t) => sum + phase(t).inMicroseconds) / _timings.length / 1000;
    setState(() {
      _fps = span > 0 ? (_timings.length - 1) / span : null;
      _buildMs = averageMs((t) => t.buildDuration);
      _rasterMs = averageMs((t) => t.rasterDuration);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fps = _fps;
    return _HudBox(
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fps == null ? '– fps' : '${fps.toStringAsFixed(0)} fps${kDebugMode ? ' (debug)' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('build ${_buildMs.toStringAsFixed(2)} ms · raster ${_rasterMs.toStringAsFixed(2)} ms'),
            ValueListenableBuilder(
              valueListenable: widget.visibleStars,
              builder: (context, visible, _) =>
                  Text('stars ${formatCount(visible)} / ${formatCount(widget.totalStars)}'),
            ),
            Text('H: hide controls', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Renderer switch, star count slider, and an explode button (a jump / drop
/// out toggle in hyperspace).
class StarfieldControlBar extends StatelessWidget {
  final StarfieldRenderer renderer;
  final ValueChanged<StarfieldRenderer> onRendererChanged;
  final int starCountStep;
  final ValueChanged<int> onStarCountStepChanged;
  final VoidCallback onExplode;
  final bool jumping;
  final VoidCallback onJumpToggled;

  const StarfieldControlBar({
    super.key,
    required this.renderer,
    required this.onRendererChanged,
    required this.starCountStep,
    required this.onStarCountStepChanged,
    required this.onExplode,
    required this.jumping,
    required this.onJumpToggled,
  });

  @override
  Widget build(BuildContext context) {
    final count = starCountSteps[starCountStep];
    return _HudBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<StarfieldRenderer>(
                segments: [for (final r in StarfieldRenderer.values) ButtonSegment(value: r, label: Text(r.label))],
                selected: {renderer},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => onRendererChanged(selection.single),
              ),
              if (renderer == StarfieldRenderer.hyperspace)
                FilledButton.tonalIcon(
                  onPressed: onJumpToggled,
                  icon: Icon(jumping ? Icons.keyboard_double_arrow_down : Icons.keyboard_double_arrow_up),
                  label: Text(jumping ? 'Drop out' : 'Jump'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: onExplode,
                  icon: const Icon(Icons.flare),
                  label: const Text('Explode'),
                ),
            ],
          ),
          Row(
            children: [
              const Text('Stars'),
              Expanded(
                child: Slider(
                  value: starCountStep.toDouble(),
                  max: starCountSteps.length - 1.0,
                  divisions: starCountSteps.length - 1,
                  label: formatCount(count),
                  onChanged: (value) => onStarCountStepChanged(value.round()),
                ),
              ),
              SizedBox(width: 56, child: Text(formatCount(count), textAlign: TextAlign.end)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HudBox extends StatelessWidget {
  final Widget child;
  const _HudBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}
