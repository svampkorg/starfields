import 'dart:ui' as ui;

/// Fragment programs and shader-generated textures used by the renderers.
/// Loaded once at start-up ([load]) so that renderers can be switched without
/// waiting.
class StarShaders {
  StarShaders._();

  /// Atlas for the "Styled" renderer: glow disc plus antialiased tail strips,
  /// painted once by `shaders/styled_atlas.frag`. Layout documented there.
  static late final ui.Image styledAtlas;

  /// Full-screen program of the "Procedural" renderer.
  static late final ui.FragmentProgram procedural;

  static const int atlasWidth = 256;
  static const int glowSize = 256;
  static const int tailBands = 32;
  static const int tailBandHeight = 20;
  static const int atlasHeight = glowSize + tailBands * tailBandHeight;

  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final program = await ui.FragmentProgram.fromAsset('shaders/styled_atlas.frag');
    final shader = program.fragmentShader();
    final recorder = ui.PictureRecorder();
    // A plain rect: here the shader runs once per atlas pixel.
    ui.Canvas(recorder)
        .drawRect(ui.Rect.fromLTWH(0, 0, atlasWidth.toDouble(), atlasHeight.toDouble()), ui.Paint()..shader = shader);
    final picture = recorder.endRecording();
    styledAtlas = await picture.toImage(atlasWidth, atlasHeight);
    picture.dispose();
    shader.dispose();
    procedural = await ui.FragmentProgram.fromAsset('shaders/procedural_stars.frag');
    _loaded = true;
  }
}
