#!/bin/bash
# Build libghostty static library from ghostty source.
# Must be run once before opening the Xcode project.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GHOSTTY_SRC="/tmp/ghostty-src"

if [ ! -d "$GHOSTTY_SRC" ]; then
  git clone https://github.com/ghostty-org/ghostty "$GHOSTTY_SRC"
fi

cd "$GHOSTTY_SRC"
zig build -Doptimize=ReleaseFast -Demit-macos-app=false

mkdir -p "$PROJECT_DIR/Vendor/ghostty/include"
mkdir -p "$PROJECT_DIR/Vendor/ghostty/lib"

XCFW="$GHOSTTY_SRC/macos/GhosttyKit.xcframework/macos-arm64_x86_64"
if [ -f "$XCFW/ghostty-internal.a" ]; then
  cp "$XCFW/Headers/ghostty.h" "$PROJECT_DIR/Vendor/ghostty/include/"
  cp "$XCFW/ghostty-internal.a" "$PROJECT_DIR/Vendor/ghostty/lib/libghostty.a"
elif [ -f "$GHOSTTY_SRC/zig-out/lib/libghostty.a" ]; then
  cp "$GHOSTTY_SRC/zig-out/include/ghostty.h" "$PROJECT_DIR/Vendor/ghostty/include/"
  cp "$GHOSTTY_SRC/zig-out/lib/libghostty.a" "$PROJECT_DIR/Vendor/ghostty/lib/"
elif [ -f "$GHOSTTY_SRC/zig-out/lib/libghostty.dylib" ]; then
  cp "$GHOSTTY_SRC/zig-out/include/ghostty.h" "$PROJECT_DIR/Vendor/ghostty/include/"
  cp "$GHOSTTY_SRC/zig-out/lib/libghostty.dylib" "$PROJECT_DIR/Vendor/ghostty/lib/"
else
  echo "ERROR: libghostty not found in either GhosttyKit.xcframework or $GHOSTTY_SRC/zig-out/lib/" >&2
  exit 1
fi

mkdir -p "$PROJECT_DIR/Vendor/ghostty/share"
if [ -d "$GHOSTTY_SRC/zig-out/share/ghostty" ]; then
  rsync -a "$GHOSTTY_SRC/zig-out/share/ghostty/" "$PROJECT_DIR/Vendor/ghostty/share/ghostty/"
elif [ -d "$GHOSTTY_SRC/src/shell-integration" ]; then
  mkdir -p "$PROJECT_DIR/Vendor/ghostty/share/ghostty"
  rsync -a "$GHOSTTY_SRC/src/shell-integration/" "$PROJECT_DIR/Vendor/ghostty/share/ghostty/shell-integration/"
fi

THEMES_DST="$PROJECT_DIR/Vendor/ghostty/share/ghostty/themes"
if [ ! -d "$THEMES_DST" ] || [ -z "$(ls -A "$THEMES_DST" 2>/dev/null)" ]; then
  for candidate in \
    "$GHOSTTY_SRC/zig-out/share/ghostty/themes" \
    "$GHOSTTY_SRC/vendor/iTerm2-Color-Schemes/ghostty" \
    "$GHOSTTY_SRC/themes"; do
    if [ -d "$candidate" ] && [ -n "$(ls -A "$candidate" 2>/dev/null)" ]; then
      mkdir -p "$THEMES_DST"
      rsync -a "$candidate/" "$THEMES_DST/"
      break
    fi
  done
fi

echo "Vendor build completed successfully!"
