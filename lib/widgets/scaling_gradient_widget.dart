import 'package:flutter/material.dart';

class ScalingGradientWidget extends StatelessWidget {
  const ScalingGradientWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        backgroundBlendMode: BlendMode.hardLight,
        gradient: RadialGradient(
          radius: 1.5,
          colors: [
            Colors.white,
            Colors.blue,
            Colors.transparent,
          ],
          stops: [0.02, 0.2, 1.0],
        ),
      ),
    );
  }
}
