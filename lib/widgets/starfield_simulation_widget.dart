import 'dart:async';

import 'dart:math';
import 'package:flutter/material.dart';

class StarfieldSimulationWidget extends StatefulWidget {
  final int numberOfStars;
  final int speed;
  final bool explode;
  const StarfieldSimulationWidget({Key? key, required this.numberOfStars, this.speed = 8, this.explode = false}) : super(key: key);

  @override
  State<StarfieldSimulationWidget> createState() => _StarfieldSimulationWidgetState();
}

class _StarfieldSimulationWidgetState extends State<StarfieldSimulationWidget> with SingleTickerProviderStateMixin {
  final List<Star> _stars = [];
  late AnimationController starAnimation;
  late AnimationController? explosionAnimation;
  late Size windowSize;
  bool isInit = false;
  late Timer t;

  @override
  void initState() {
    super.initState();
    if (!isInit) {
      t = Timer(Duration(milliseconds: widget.speed), _updateStars);
      //_initTimer(context);
      switch (widget.explode) {
        case false:
          starAnimation = AnimationController(vsync: this, duration: const Duration(seconds: 1));
          starAnimation.repeat();
          break;
        case true:
          _initExplosion();
          starAnimation = AnimationController(vsync: this, duration: const Duration(seconds: 1));
          break;
      }
      isInit = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    windowSize = MediaQuery.of(context).size;
    //t = Timer(Duration(milliseconds: widget.speed), _updateStars);
  }

  //void _initTimer(BuildContext context) {
  //  double durationMicroSeconds = 3000; //* liveGameData.time as double;
  //  if (durationMicroSeconds <= 0) durationMicroSeconds = 12000;
  //  if (t.isActive) t.cancel();
  //  t = Timer(
  //      Duration(microseconds: durationMicroSeconds.toInt()), _updateStars);
  //}

  void _initExplosion() {
    while (_stars.length <= widget.numberOfStars) {
      _stars.add(Star(windowXSize: windowSize.width, windowYSize: windowSize.height, startCenter: true));
    }
  }

  void _updateStars() {
    if (!isInit || !mounted) return;
    if (_stars.length < widget.numberOfStars && !widget.explode) {
      _stars.add(Star(windowXSize: windowSize.width, windowYSize: windowSize.height));
    }
    for (int index = 0; index < _stars.length; index++) {
      _stars[index].move();
    }
    t = Timer(Duration(milliseconds: widget.speed), _updateStars);
  }

  @override
  void dispose() {
    _stars.clear();
    if (t.isActive) {
      t.cancel();
    }
    starAnimation.stop();
    starAnimation.dispose();
    super.dispose();
  }

  void stopStars() {
    if (t.isActive) {
      t.cancel();
    } else {
      t = Timer(Duration(milliseconds: widget.speed), _updateStars);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          isComplex: true,
          size: windowSize,
          painter: StarsPainter(stars: _stars, listenable: starAnimation, screenSize: windowSize),
        ),
        if (widget.explode)
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutSine,
            tween: Tween<double>(begin: 1.0, end: 0.0),
            onEnd: () => starAnimation.repeat(),
            builder:
                (context, value, child) => Center(
                  child: Container(
                    height: windowSize.height,
                    width: windowSize.width,
                    decoration: BoxDecoration(
                      backgroundBlendMode: BlendMode.hardLight,
                      gradient: RadialGradient(
                        radius: value * 2.2,
                        colors: const [Colors.white, Colors.blue, Colors.transparent],
                        stops: const [0.02, 0.2, 1.0],
                      ),
                    ),
                  ),
                ),
          ),
        Center(
          child: Container(
            height: windowSize.height,
            width: windowSize.width,
            decoration: BoxDecoration(
              backgroundBlendMode: BlendMode.hue,
              gradient: RadialGradient(
                radius: 0.7,
                colors: [
                  Colors.white,
                  Colors.cyanAccent,
                  Colors.lightBlue,
                  Colors.blueAccent,
                  Colors.deepPurple,
                  Colors.deepPurple.withValues(alpha: 0.4),
                ],
                stops: const [0.00, 0.3, 0.5, 0.6, 0.8, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class StarsPainter extends CustomPainter {
  AnimationController listenable;
  List<Star> stars;
  final RadialGradient mainGradient = const RadialGradient(
    colors: [Colors.white, Colors.redAccent, Colors.transparent],
    stops: [0.0, 0.2, 0.8],
  );
  final RadialGradient tailGradient = const RadialGradient(
    colors: [
      // Colors.transparent,
      Colors.white,
      Colors.redAccent,
      Colors.transparent,
    ],
    stops: [
      0.0,
      // 0.3,
      0.6,
      1.0,
    ],
  );
  Size screenSize;
  StarsPainter({required this.listenable, required this.stars, required this.screenSize}) : super(repaint: listenable);
  @override
  void paint(Canvas canvas, Size size) {
    Paint starPaint, tailPaint;

    Pos screenCenter = Pos(screenSize.width / 2, screenSize.height / 2);
    double screenWidth = screenSize.width;
    double screenHeight = screenSize.height;

    Pos starPosition;
    double starSize;

    double widthDiff;
    double heightDiff;

    double tailXOffset;
    double tailYOffset;

    double tailOffset;

    double direction;

    for (int index = 0; index < stars.length; index++) {
      starPosition = Pos(stars[index].posX, stars[index].posY);
      starSize = stars[index].size;

      widthDiff = starPosition.x - screenCenter.x;
      heightDiff = starPosition.y - screenCenter.y;

      direction = Offset(starPosition.x, starPosition.y).direction;

      // tailXOffset = 1 / (widthDiff / heightDiff);
      // tailYOffset = 1 / (heightDiff / widthDiff);

      tailOffset = 1 / (widthDiff / heightDiff);

      starPaint =
          Paint()
            ..style = PaintingStyle.fill
            //..blendMode = BlendMode.hardLight
            ..shader = mainGradient.createShader(
              Rect.fromCircle(center: Offset(screenWidth * starPosition.x, screenHeight * starPosition.y), radius: starSize * 5),
            );

      tailPaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = starSize
            ..strokeCap = StrokeCap.round
            //..blendMode = BlendMode.hardLight
            ..shader = tailGradient.createShader(
              Rect.fromCircle(center: Offset(screenWidth * starPosition.x, screenHeight * starPosition.y), radius: starSize * 10 + 20),
            );

      Path tailPath = Path();
      tailPath.moveTo(
        screenWidth * starPosition.x, // + starSize * tailOffset,
        screenHeight * starPosition.y, // + starSize * tailOffset,
      );
      tailPath.lineTo(
        screenWidth * starPosition.x, // - starSize * tailOffset,
        screenHeight * starPosition.y, // - starSize * tailOffset,
      );
      tailPath.lineTo(screenCenter.x, screenCenter.y);
      //tailPath.close();

      canvas.drawCircle(Offset(screenWidth * starPosition.x, screenHeight * starPosition.y), starSize * 5, starPaint);
      canvas.drawPath(tailPath, tailPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class Pos {
  double x;
  double y;

  Pos(this.x, this.y);
}

enum Direction { topRight, topLeft, bottomLeft, bottomRight }

class Star {
  double velocity;
  double luminance;
  double size;

  int speed;

  late Direction direction;

  double posX, posY;

  double centerX = 0.5, centerY = 0.5;

  double? normalizedDirection;

  bool startCenter;

  static final rng = Random();

  final double windowXSize;
  final double windowYSize;

  Star({required this.windowXSize, required this.windowYSize, this.startCenter = false})
    : velocity = rng.nextDouble(),
      size = 0.1,
      speed = rng.nextInt(10) + 1,
      luminance = rng.nextDouble() * 0.5 + 0.5,
      posX = rng.nextDouble(),
      posY = rng.nextDouble();

  void move() {
    double distanceFromCenterX = centerX - posX;
    double distanceFromCenterY = centerY - posY;
    double speedFactor = 0.004;
    //If distance from originX is negative, star is in right part of screen, else left part of screen.
    //If distance from originY is negative, star is in bottom part of screen, else top part of screen.
    distanceFromCenterX.isNegative
        ? posX +=
            -distanceFromCenterX *
            speed *
            speedFactor //is right side of origin
        : posX -= distanceFromCenterX * speed * speedFactor; //is left side of origin
    distanceFromCenterY.isNegative
        ? posY +=
            -distanceFromCenterY *
            speed *
            speedFactor //is bottom side of origin
        : posY -= distanceFromCenterY * speed * speedFactor; //is top side of origin

    _setSize();
    _checkBounds();
  }

  void _setSize() {
    double growThreshold = 0.015;

    double distanceFromCenterX = centerX - posX;
    double distanceFromCenterY = centerY - posY;
    if (distanceFromCenterX > growThreshold ||
        distanceFromCenterX < -growThreshold ||
        distanceFromCenterY > growThreshold ||
        distanceFromCenterY < -growThreshold) {
      //"lookup table" for star growth depending on speed/distance
      switch (speed) {
        case 1:
          size += 0.001;
          break;
        case 2:
          size += 0.003;
          break;
        case 3:
          size += 0.006;
          break;
        case 4:
          size += 0.016;
          break;
        case 5:
          size += 0.030;
          break;
        case 6:
          size += 0.050;
          break;
        case 7:
          size += 0.070;
          break;
        case 8:
          size += 0.090;
          break;
        case 9:
          size += 0.120;
          break;
        case 10:
          size += 0.150;
          break;
      }
    }
  }

  void _checkBounds() {
    //if outside of window
    if (posX > 1.2 || posX < -0.2) _resetStar();
    if (posY > 1.2 || posY < -0.2) _resetStar();
  }

  void _resetStar() {
    if (startCenter) return;
    //random bool to determin initial offset from center on either axle for reasons
    bool addXOffst = rng.nextBool();
    bool addYOffset = rng.nextBool();
    //the offset from center when repositioning, again.. reasons
    double xOffset = rng.nextDouble() * 0.0001; //rng.nextInt(20) + 10;
    double yOffset = rng.nextDouble() * 0.0001; //rng.nextInt(20) + 10;
    posX = centerX;
    posY = centerY;
    addXOffst ? posX += xOffset : posX -= xOffset;
    addYOffset ? posY += yOffset : posY -= yOffset;

    size = 0.1;
  }
}
