import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starfields/main.dart';
import 'package:starfields/renderers/star_shaders.dart';
import 'package:starfields/widgets/starfield_hud.dart';
import 'package:starfields/widgets/starfield_simulation_widget.dart';

void main() {
  setUpAll(StarShaders.load);

  testWidgets('starfield animates without errors', (tester) async {
    await tester.pumpWidget(const MyApp());
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(StarfieldSimulationWidget), findsOneWidget);
  });

  group('controls', () {
    Future<void> pumpFrames(WidgetTester tester, int frames) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('slider changes the star count without restarting the field', (tester) async {
      await tester.pumpWidget(const MyApp());
      await pumpFrames(tester, 150); // all 200 stars spawned (one per 8 ms)
      expect(find.text('stars 200 / 200'), findsOneWidget);

      tester.widget<Slider>(find.byType(Slider)).onChanged!(starCountSteps.indexOf(10000).toDouble());
      await pumpFrames(tester, 2);
      expect(find.text('stars 10,000 / 10,000'), findsOneWidget);
    });

    int visibleStars(WidgetTester tester) {
      final text = tester.widget<Text>(find.textContaining('stars ')).data!;
      return int.parse(text.split(' ')[1].replaceAll(',', ''));
    }

    // The growing core: the explosion's hard-light gradient (the static one
    // from ScalingGradientWidget has radius 1.5).
    Iterable<double> coreRadius(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.backgroundBlendMode == BlendMode.hardLight && d.gradient is RadialGradient)
        .map((d) => (d.gradient! as RadialGradient).radius)
        .where((radius) => radius != 1.5);

    testWidgets('explode: spawning stops and the core grows, then everything bursts out', (tester) async {
      await tester.pumpWidget(const MyApp());
      await pumpFrames(tester, 600); // ~10 s: a steady starfield
      expect(visibleStars(tester), 200);
      expect(coreRadius(tester), isEmpty);

      await tester.tap(find.text('Explode'));
      await pumpFrames(tester, 30);
      final early = coreRadius(tester).single;
      await pumpFrames(tester, 60); // ~1.4 s in
      expect(coreRadius(tester).single, greaterThan(early)); // the core grows
      expect(visibleStars(tester), lessThan(150)); // absorbed and not respawned

      await pumpFrames(tester, 30); // past the burst
      expect(visibleStars(tester), 200);
      await pumpFrames(tester, 40); // flash over
      expect(coreRadius(tester), isEmpty);
      expect(find.text('Explode'), findsOneWidget); // ready for another one
    });

    testWidgets('hyperspace renders, and explode becomes a jump that keeps running', (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.tap(find.text('Hyperspace'));
      await pumpFrames(tester, 3);
      expect(tester.takeException(), isNull);
      expect(find.text('stars 200 / 200'), findsOneWidget);

      await tester.tap(find.text('Jump'));
      await pumpFrames(tester, 2);
      expect(find.text('Drop out'), findsOneWidget);
      // Unlike an explosion, a jump never runs out of stars.
      await tester.pump(const Duration(seconds: 30));
      await pumpFrames(tester, 2);
      expect(tester.binding.hasScheduledFrame, isTrue);

      await tester.tap(find.text('Drop out'));
      await pumpFrames(tester, 2);
      expect(find.text('Jump'), findsOneWidget);
    });

    testWidgets('switching to the styled renderer keeps the stars', (tester) async {
      await tester.pumpWidget(const MyApp());
      await pumpFrames(tester, 150);
      expect(find.text('stars 200 / 200'), findsOneWidget);

      await tester.tap(find.text('Styled'));
      await pumpFrames(tester, 2);
      final button = tester.widget<SegmentedButton<StarfieldRenderer>>(find.byType(SegmentedButton<StarfieldRenderer>));
      expect(button.selected, {StarfieldRenderer.styled});
      expect(find.text('stars 200 / 200'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('procedural renderer pauses the simulation and reports what it draws', (tester) async {
      await tester.pumpWidget(const MyApp());
      await pumpFrames(tester, 150);

      await tester.tap(find.text('Procedural'));
      await pumpFrames(tester, 3);
      expect(tester.takeException(), isNull);
      final button = tester.widget<SegmentedButton<StarfieldRenderer>>(find.byType(SegmentedButton<StarfieldRenderer>));
      expect(button.selected, {StarfieldRenderer.procedural});
      expect(find.text('stars 200 / 200'), findsOneWidget);

      // Back to the CPU renderers: the same starfield carries on.
      await tester.tap(find.text('Batched'));
      await pumpFrames(tester, 3);
      expect(find.text('stars 200 / 200'), findsOneWidget);
    });

    testWidgets('H hides and shows the controls', (tester) async {
      await tester.pumpWidget(const MyApp());
      await pumpFrames(tester, 2);
      expect(find.byType(FrameStatsPanel), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await pumpFrames(tester, 1);
      expect(find.byType(FrameStatsPanel), findsNothing);
      expect(find.byType(StarfieldControlBar), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await pumpFrames(tester, 1);
      expect(find.byType(FrameStatsPanel), findsOneWidget);
    });
  });
}
