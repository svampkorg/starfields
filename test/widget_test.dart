import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starfields/main.dart';
import 'package:starfields/renderers/star_shaders.dart';
import 'package:starfields/widgets/supernova.dart';
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

    // Radii of the hard-light core gradients: the normal core (1.5) and,
    // during an explosion, the explosion's own growing core.
    List<double> coreRadii(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.backgroundBlendMode == BlendMode.hardLight && d.gradient is RadialGradient)
        .map((d) => (d.gradient! as RadialGradient).radius)
        .toList();

    testWidgets('explode: core grows, vanishes at the burst, pauses, then regrows with the stars', (tester) async {
      await tester.pumpWidget(const MyApp());
      await pumpFrames(tester, 600); // ~10 s: a steady starfield
      expect(visibleStars(tester), 200);
      expect(coreRadii(tester), [1.5]);

      await tester.tap(find.text('Explode'));
      await pumpFrames(tester, 30);
      final early = coreRadii(tester).first;
      await pumpFrames(tester, 60); // ~1.4 s in: charging
      expect(coreRadii(tester), [greaterThan(early), 1.5]);
      expect(visibleStars(tester), lessThan(150)); // absorbed and not respawned

      bool supernova() =>
          find.byWidgetPredicate((w) => w is CustomPaint && w.painter is SupernovaPainter).evaluate().isNotEmpty;
      await pumpFrames(tester, 30); // just past the burst
      expect(coreRadii(tester), isEmpty); // both cores gone at once
      expect(supernova(), isTrue); // flash, shockwave, afterglow
      // Nearly every star bursts out (a few old ones have left and now wait).
      expect(visibleStars(tester), greaterThan(190));

      await pumpFrames(tester, 140); // ~2.35 s into the 2.5 s pause: still dark
      expect(coreRadii(tester), isEmpty);

      await pumpFrames(tester, 90); // regrowing
      expect(coreRadii(tester).single, inExclusiveRange(0, 1.5));

      await pumpFrames(tester, 200); // sequence over
      expect(coreRadii(tester), [1.5]);
      expect(supernova(), isFalse);
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
