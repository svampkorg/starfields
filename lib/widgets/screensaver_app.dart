import 'package:flutter/material.dart';
import 'package:starfields/widgets/starfield_simulation_widget.dart';

/// The screen saver's widget tree (macos_saver/): fixed settings, no HUD and
/// no input, since the host dismisses the saver on any key or mouse event.
class ScreensaverApp extends StatelessWidget {
  const ScreensaverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.black,
        child: StarfieldSimulationWidget(numberOfStars: 2000, renderer: StarfieldRenderer.batched),
      ),
    );
  }
}
