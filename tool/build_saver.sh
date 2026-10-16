#!/bin/bash
# Builds the macOS screen saver (Starfields.saver) around the Flutter release
# build and optionally installs it into ~/Library/Screen Savers.
#
#   tool/build_saver.sh            # flutter build + assemble + sign
#   tool/build_saver.sh --install  # ... and install (replaces an older copy)
#   SKIP_FLUTTER_BUILD=1 tool/build_saver.sh   # reuse the last release build
#
# The saver runs the `screensaverMain` entry point (lib/main.dart) in a
# FlutterEngine hosted by macos_saver/StarfieldsSaverView.swift, on the main
# display only. Also builds build/saver/test_host (macos_saver/test_host.swift).
#
# Start it now: open -a ScreenSaverEngine. Dismiss it with the mouse; do not
# kill ScreenSaverEngine, or loginwindow keeps thinking a saver is running and
# refuses to start another until the session is locked and unlocked.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
APP="$ROOT/build/macos/Build/Products/Release/starfields.app"
OUT="$ROOT/build/saver"
SAVER="$OUT/Starfields.saver"
FLUTTER_ROOT="$(dirname "$(dirname "$(command -v flutter)")")"
# The release app's FlutterMacOS.framework has no headers/modules; compile
# against the engine artifact and embed the copy from the app.
SDK_FRAMEWORKS="$FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64-release/FlutterMacOS.xcframework/macos-arm64_x86_64"
MIN_MACOS=12.0

if [[ -z "${SKIP_FLUTTER_BUILD:-}" ]]; then
  flutter build macos --release
fi

rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Frameworks" "$SAVER/Contents/Resources" "$OUT/obj"

for arch in arm64 x86_64; do
  xcrun swiftc \
    -target "$arch-apple-macos$MIN_MACOS" \
    -O -module-name StarfieldsSaver \
    -emit-library -o "$OUT/obj/Starfields-$arch" \
    -F "$SDK_FRAMEWORKS" -framework FlutterMacOS -framework ScreenSaver \
    -Xlinker -rpath -Xlinker @loader_path/../Frameworks \
    macos_saver/StarfieldsSaverView.swift
done
lipo -create "$OUT/obj/Starfields-arm64" "$OUT/obj/Starfields-x86_64" -output "$SAVER/Contents/MacOS/Starfields"

cp macos_saver/Info.plist "$SAVER/Contents/Info.plist"
ditto "$APP/Contents/Frameworks/FlutterMacOS.framework" "$SAVER/Contents/Frameworks/FlutterMacOS.framework"
ditto "$APP/Contents/Frameworks/App.framework" "$SAVER/Contents/Frameworks/App.framework"

# Ad-hoc signature: fine on this machine. Sharing needs Developer ID + notarization.
codesign --force --sign - "$SAVER/Contents/Frameworks/App.framework"
codesign --force --sign - "$SAVER/Contents/Frameworks/FlutterMacOS.framework"
codesign --force --sign - "$SAVER"
codesign --verify --deep --strict "$SAVER"
du -sh "$SAVER"

# Stand-in host for quick tests without System Settings (see the file header).
xcrun swiftc -O -o "$OUT/test_host" -framework ScreenSaver macos_saver/test_host.swift

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Library/Screen Savers"
  mkdir -p "$DEST"
  rm -rf "$DEST/Starfields.saver"
  ditto "$SAVER" "$DEST/Starfields.saver"
  # A running host keeps the old code loaded.
  killall legacyScreenSaver 2>/dev/null || true
  echo "Installed to $DEST/Starfields.saver"
fi
