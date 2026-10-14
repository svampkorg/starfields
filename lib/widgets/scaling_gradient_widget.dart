import 'package:flutter/material.dart';

/// The bright core in the middle of the starfield.
class ScalingGradientWidget extends StatelessWidget {
  /// Size relative to the normal core; 0 hides it.
  final double scale;

  const ScalingGradientWidget({super.key, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    if (scale <= 0) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        backgroundBlendMode: BlendMode.hardLight,
        gradient: RadialGradient(
          radius: 1.5 * scale,
          colors: const [Colors.white, Colors.blue, Colors.transparent],
          stops: const [0.02, 0.2, 1.0],
        ),
      ),
    );
  }
}
