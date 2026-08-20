#!/bin/bash
# Clean-rebuild and relaunch MuH Debug app.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Killing running MuH…"
pkill -f "Debug/MuH.app" 2>/dev/null || true
sleep 0.5

echo "==> Regenerating Xcode project (XcodeGen)…"
xcodegen generate >/dev/null

echo "==> Cleaning Xcode build cache…"
xcodebuild -project MuH.xcodeproj -scheme MuH -configuration Debug clean >/dev/null

echo "==> Removing DerivedData for MuH…"
rm -rf ~/Library/Developer/Xcode/DerivedData/MuH-*

echo "==> Building (fresh)…"
xcodebuild -project MuH.xcodeproj -scheme MuH -configuration Debug build | tail -3

APP=$(find ~/Library/Developer/Xcode/DerivedData -name "MuH.app" -type d 2>/dev/null | head -1)
if [ -z "$APP" ]; then
  echo "!! MuH.app not found after build" >&2
  exit 1
fi

echo "==> Launching: $APP"
open "$APP"
sleep 0.5
pgrep -lf "Debug/MuH.app" || echo "!! launch failed"
