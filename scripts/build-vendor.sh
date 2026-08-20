#!/bin/bash
# Build libghostty static library from a pinned Ghostty source revision.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GHOSTTY_SRC="${GHOSTTY_SRC:-/tmp/ghostty-src}"
GHOSTTY_COMMIT="4c6215bb8ee186b5c829457a9a9a9c936f2337bf"
MINIMUM_ZIG_VERSION="0.16.0"

if ! command -v zig >/dev/null 2>&1; then
  echo "ERROR: Zig ${MINIMUM_ZIG_VERSION} or a compatible 0.16.x release is required but was not found in PATH." >&2
  exit 1
fi

ZIG_VERSION="$(zig version)"
IFS=. read -r ZIG_MAJOR ZIG_MINOR ZIG_PATCH _ <<< "$ZIG_VERSION"
IFS=. read -r MINIMUM_MAJOR MINIMUM_MINOR MINIMUM_PATCH <<< "$MINIMUM_ZIG_VERSION"
if [[ "$ZIG_MAJOR" != "$MINIMUM_MAJOR" || "$ZIG_MINOR" != "$MINIMUM_MINOR" || "$ZIG_PATCH" -lt "$MINIMUM_PATCH" ]]; then
  echo "ERROR: Zig ${MINIMUM_ZIG_VERSION} or a compatible 0.16.x release is required; found ${ZIG_VERSION}." >&2
  exit 1
fi

if [ ! -d "$GHOSTTY_SRC" ]; then
  git clone https://github.com/ghostty-org/ghostty "$GHOSTTY_SRC"
fi

cd "$GHOSTTY_SRC"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: $GHOSTTY_SRC is not a Ghostty git checkout." >&2
  exit 1
fi
git fetch --quiet origin "$GHOSTTY_COMMIT"
git checkout --quiet --detach "$GHOSTTY_COMMIT"
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
else
  echo "ERROR: static libghostty.a was not found in Ghostty output." >&2
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
