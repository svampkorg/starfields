import 'package:flutter/material.dart';

class ScalingGradientWidget extends StatelessWidget {
  const ScalingGradientWidget({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Size windowSize = MediaQuery.of(context).size;
    //print("windowSize.height: ${windowSize.height}");
    return Container(
      height: windowSize.height,
      width: windowSize.width,
      decoration: const BoxDecoration(
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
