# starfields

<img width="2223" height="1222" alt="image" src="https://github.com/user-attachments/assets/25490c71-0278-4214-8de8-966763774c09" />

A "travel through space" starfield: a Flutter app with four renderers, and a native
**macOS screen saver** with movie-style jumps to light speed.

## What's in here

| | What | Where |
|---|---|---|
| **Starfields Metal** (screen saver) | Native Metal screen saver, two styles: **Hyperspace** — a slow cruise through the stars, and every so often a jump to light speed: the stars stretch out, the ship creeps up to speed and then punches through; **Procedural** — glowing stars streaming out of the center, colored by speed. Runs on every display. | `macos_saver_metal/` |
| Starfields (screen saver, experimental) | The Flutter app itself inside a screen saver. Main display only — see [below](#the-flutter-screen-saver-experimental). | `macos_saver/` |
| The app | Flutter app (macOS desktop) with four renderers: Batched, Styled, Procedural and Hyperspace, plus a supernova explosion. | `lib/`, `shaders/` |

The screen saver and the app share their shader sources
(`shaders/hyperspace_streaks.glsl`, `shaders/procedural_stars.glsl`): the build turns the
GLSL into Metal with Flutter's own shader compiler.

## The Starfields Metal screen saver

### Requirements

- **macOS 12 or later**; macOS 14 or later recommended (each display is then paced by its
  own refresh; older systems fall back to the screen saver host's timer). Developed and
  tested on Apple silicon; the build is universal (arm64 + x86_64).
- **Xcode or the Xcode Command Line Tools** (`xcode-select --install`): `swiftc`, `lipo`,
  `codesign` and the macOS SDK. No Metal toolchain needed — the shaders are compiled when
  the saver starts.
- **Flutter** (stable channel; developed with 3.47) on your `PATH`, for its shader
  compiler `impellerc`. After installing Flutter, fetch its macOS tools once:

  ```bash
  flutter precache --macos
  ```

### Build and install

```bash
git clone https://github.com/svampkorg/starfields.git
cd starfields
tool/build_metal_saver.sh --install
```

This builds `build/metal_saver/StarfieldsMetal.saver` and copies it to
`~/Library/Screen Savers/`. Then open **System Settings → Screen Saver**, pick
**Starfields Metal** and use **Preview** to try it.

Without `--install` the script only builds; install by hand by copying the `.saver` to
`~/Library/Screen Savers/` (or double-clicking it).

The script signs the saver ad hoc. That is all macOS needs for a saver you built
yourself.

### Options

**System Settings → Screen Saver → Starfields Metal → Options…**

| Option | Range | Default |
|---|---|---|
| Style | Hyperspace / Procedural | Hyperspace |
| Jump to light speed (Hyperspace) | on / off (off: an endless cruise) | on |
| Time between jumps (Hyperspace) | 10–120 s | 30 s |
| Light speed lasts (Hyperspace) | 5–60 s | 20 s |
| Stars | 500–8000 (Procedural: 500–5000) | 2000 |

### A prebuilt copy from someone else

A `.saver` that was downloaded carries macOS's quarantine flag and an ad-hoc signature
macOS won't trust. Building it yourself avoids that. If you do use a downloaded copy and
trust its source, remove the flag before installing:

```bash
xattr -dr com.apple.quarantine StarfieldsMetal.saver
```

(or allow it under **System Settings → Privacy & Security** after the first blocked
attempt).

### Uninstall

Remove `~/Library/Screen Savers/StarfieldsMetal.saver` (and `Starfields.saver`, if you
installed the Flutter one).

### Good to know

- **60 fps on every display**, on purpose: a screen saver need not burn energy at 120 or
  240 Hz (and on a 240 Hz display the system's screen saver host showed glitches at
  higher rates).
- The **preview in System Settings stops after you click OK** in Options — that's macOS
  creating a new preview without starting it. Reopen System Settings to see it again; your
  settings are saved either way.
- New settings take effect the next time the screen saver starts.

## The Flutter screen saver (experimental)

`tool/build_saver.sh --install` builds **Starfields**, the Flutter app running inside a
screen saver (Batched renderer). It needs full **Xcode** (for `flutter build macos`) and
renders on the **main display only**: inside the macOS screen saver host, more than one
Flutter view broke (GPU hangs, wrong blending), while a single one runs at full speed. The
native Metal saver above has no such limit.

## The app

```bash
flutter run -d macos
```

Pick a renderer and a star count in the control bar; **Explode** sets off a supernova (in
Hyperspace: **Jump** to light speed). Keys: **H** hides the controls, **F** toggles full
screen.

## Development

Both screen savers come with a stand-in for the macOS screen saver host, so they can be
tried without System Settings:

```bash
tool/build_metal_saver.sh            # also builds build/metal_saver/test_host
build/metal_saver/test_host build/metal_saver/StarfieldsMetal.saver 20            # every display
build/metal_saver/test_host build/metal_saver/StarfieldsMetal.saver 20 --window   # one window
build/metal_saver/test_host build/metal_saver/StarfieldsMetal.saver 5 --window --configure
STARFIELDS_CRUISE_SECONDS=3 STARFIELDS_LIGHT_SECONDS=6 \
  build/metal_saver/test_host build/metal_saver/StarfieldsMetal.saver 12 --window \
  --shots 2.5,4,6 --shot-prefix /tmp/shot      # screenshots at those seconds
```

Environment overrides for test runs (they don't reach the real screen saver host):
`STARFIELDS_JUMPS=0/1`, `STARFIELDS_CRUISE_SECONDS`, `STARFIELDS_LIGHT_SECONDS`,
`STARFIELDS_STARS`, `STARFIELDS_RENDERER=hyperspace/procedural`, `STARFIELDS_RENDER_SCALE`
(default 1.5 for Hyperspace and 0.5 for Procedural, at most the display's),
`STARFIELDS_MAX_FPS` (default 60).

The saver logs fps, CPU and GPU time per frame every two seconds:

```bash
log stream --predicate 'subsystem == "com.bosse.starfields.metalsaver"'
```

Start the selected screen saver right away with `open -a ScreenSaverEngine` and dismiss
it with the mouse — don't kill `ScreenSaverEngine`, or macOS refuses to start another
screen saver until you lock and unlock.

App checks: `flutter analyze`, `flutter test`. Frame benchmark:
`flutter run --profile -d macos -t tool/frame_bench.dart` (options in the file).

## License

MIT — see [LICENSE](LICENSE).
