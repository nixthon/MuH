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

# Xcode build/launch 会把 DerivedData 里的 Debug 版注册到 LaunchServices,
# 导致 Spotlight/Docker 出现两个 MuH;启动后注销该 Debug 注册,仅保留 /Applications 正式版。
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREG" ]; then
  while IFS= read -r dbgApp; do
    "$LSREG" -u "$dbgApp" 2>/dev/null || true
  done < <(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Debug/MuH.app" -type d 2>/dev/null)
fi
