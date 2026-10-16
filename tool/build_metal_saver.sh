#!/bin/bash
# Builds the native Metal screen saver (StarfieldsMetal.saver, option B) and
# optionally installs it into ~/Library/Screen Savers, next to the Flutter
# saver (tool/build_saver.sh).
#
#   tool/build_metal_saver.sh            # compile + assemble + sign
#   tool/build_metal_saver.sh --install  # ... and install (replaces an older copy)
#
# The fragment shader is generated from shaders/hyperspace_saver.frag with
# impellerc (from the Flutter cache) and, like FullScreen.metal, compiled at
# runtime from source, so no offline Metal toolchain is needed. Also builds build/metal_saver/test_host
# (macos_saver/test_host.swift).
#
# Start it now: open -a ScreenSaverEngine. Dismiss it with the mouse; do not
# kill ScreenSaverEngine (loginwindow then refuses new starts until the
# session is locked and unlocked).
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="$PWD/build/metal_saver"
SAVER="$OUT/StarfieldsMetal.saver"
MIN_MACOS=12.0
FLUTTER_ROOT="$(dirname "$(dirname "$(command -v flutter)")")"
ENGINE="$FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64"
IMPELLERC="$ENGINE/impellerc"

rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources" "$OUT/obj"

for arch in arm64 x86_64; do
  xcrun swiftc \
    -target "$arch-apple-macos$MIN_MACOS" \
    -O -module-name StarfieldsMetalSaver \
    -emit-library -o "$OUT/obj/StarfieldsMetal-$arch" \
    -framework ScreenSaver -framework Metal -framework QuartzCore \
    macos_saver_metal/StarfieldsMetalSaverView.swift macos_saver_metal/HyperspaceDrive.swift
done
lipo -create "$OUT/obj/StarfieldsMetal-arm64" "$OUT/obj/StarfieldsMetal-x86_64" \
  -output "$SAVER/Contents/MacOS/StarfieldsMetal"

cp macos_saver_metal/Info.plist "$SAVER/Contents/Info.plist"
cp macos_saver_metal/FullScreen.metal "$SAVER/Contents/Resources/"
# One shader source: Flutter's own shader compiler turns the runtime-effect
# GLSL into Metal source (no --iplr: plain MSL text, not a Flutter bundle).
"$IMPELLERC" --runtime-stage-metal --input-type=frag \
  --input=shaders/hyperspace_saver.frag --sl="$SAVER/Contents/Resources/HyperspaceSaver.metal" \
  --spirv="$OUT/obj/hyperspace_saver.spv" --include=shaders --include="$ENGINE/shader_lib"

# Ad-hoc signature: fine on this machine. Sharing needs Developer ID + notarization.
codesign --force --sign - "$SAVER"
codesign --verify --deep --strict "$SAVER"
du -sh "$SAVER"

xcrun swiftc -O -o "$OUT/test_host" -framework ScreenSaver macos_saver/test_host.swift

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Library/Screen Savers"
  mkdir -p "$DEST"
  rm -rf "$DEST/StarfieldsMetal.saver"
  ditto "$SAVER" "$DEST/StarfieldsMetal.saver"
  # A running host keeps the old code loaded.
  killall legacyScreenSaver 2>/dev/null || true
  echo "Installed to $DEST/StarfieldsMetal.saver"
fi
