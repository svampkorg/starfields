import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starfields/renderers/star_shaders.dart';
import 'package:starfields/widgets/scaling_gradient_widget.dart';
import 'package:starfields/widgets/starfield_hud.dart';
import 'package:starfields/widgets/starfield_simulation_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StarShaders.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Starfields',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
      ),
      home: const MyHomePage(title: 'Android Auto Demo Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final ValueNotifier<int> _visibleStars = ValueNotifier(0);
  int _starCountStep = starCountSteps.indexOf(200);
  StarfieldRenderer _renderer = StarfieldRenderer.batched;
  int _explosions = 0;
  bool _jumping = false;
  bool _showControls = true;

  int get _starCount => starCountSteps[_starCountStep];

  @override
  void dispose() {
    _visibleStars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.keyH): () => setState(() => _showControls = !_showControls)},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              StarfieldSimulationWidget(
                numberOfStars: _starCount,
                explosions: _explosions,
                jump: _jumping,
                renderer: _renderer,
                onVisibleCountChanged: (count) => _visibleStars.value = count,
              ),
              const ScalingGradientWidget(),
              // Above the blended overlays, so the controls are not tinted.
              if (_showControls)
                SafeArea(
                  minimum: const EdgeInsets.all(16),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: FrameStatsPanel(visibleStars: _visibleStars, totalStars: _starCount),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: StarfieldControlBar(
                            renderer: _renderer,
                            onRendererChanged: (renderer) => setState(() => _renderer = renderer),
                            starCountStep: _starCountStep,
                            onStarCountStepChanged: (step) => setState(() => _starCountStep = step),
                            onExplode: () => setState(() => _explosions++),
                            jumping: _jumping,
                            onJumpToggled: () => setState(() => _jumping = !_jumping),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
