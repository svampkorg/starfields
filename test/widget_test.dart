import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starfields/main.dart';
import 'package:starfields/widgets/starfield_simulation_widget.dart';

void main() {
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
}
