import 'package:starfields/widgets/scaling_gradient_widget.dart';
import 'package:starfields/widgets/starfield_simulation_widget.dart';
import 'package:flutter/material.dart';

void main() {
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
      theme: ThemeData(primarySwatch: Colors.blue),
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
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [StarfieldSimulationWidget(numberOfStars: 200), ScalingGradientWidget()]),
    );
  }
}
