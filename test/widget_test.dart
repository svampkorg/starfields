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

  testWidgets('explode mode renders and stops ticking once all stars are gone', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StarfieldSimulationWidget(numberOfStars: 50, explode: true)));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // A star whose origin is almost exactly at the center can take minutes to
    // leave the screen; jump far ahead so all of them have.
    await tester.pump(const Duration(hours: 1));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
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

    testWidgets('explode and restore', (tester) async {
      await tester.pumpWidget(const MyApp());
      await pumpFrames(tester, 10);

      await tester.tap(find.text('Explode'));
      await pumpFrames(tester, 2);
      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('stars 200 / 200'), findsOneWidget); // every star at once

      await tester.pump(const Duration(hours: 1));
      await pumpFrames(tester, 2);
      expect(find.text('stars 0 / 200'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.tap(find.text('Restore'));
      await pumpFrames(tester, 150);
      expect(find.text('Explode'), findsOneWidget);
      expect(find.text('stars 200 / 200'), findsOneWidget);
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
