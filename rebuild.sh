#!/bin/bash
# Build MuH Release, install to /Applications, launch, and clean up test artifacts.
#
# Usage:
#   ./rebuild.sh          Full flow: kill app → xcodegen → build Release → install → launch → cleanup
#   ./rebuild.sh clean    Cleanup only: remove build dirs and stale LaunchServices registrations
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Remove local/Xcode/tmp build outputs and unregister every MuH.app copy that
# lives outside /Applications, so Spotlight/LaunchServices only shows the
# official install (test builds registered from DerivedData cause duplicates).
cleanup() {
    echo "==> Cleaning build artifacts…"
    rm -rf "$SCRIPT_DIR/build"
    rm -rf ~/Library/Developer/Xcode/DerivedData/MuH-*
    rm -rf /tmp/muh-build-*

    echo "==> Unregistering test/dev MuH copies from LaunchServices…"
    if [ -x "$LSREG" ]; then
        while IFS= read -r app; do
            [ -e "$app" ] || continue
            echo "    lsregister -u $app"
            "$LSREG" -u "$app" 2>/dev/null || true
        done < <(find ~/Library/Developer/Xcode/DerivedData /tmp -maxdepth 8 -name "MuH.app" -type d 2>/dev/null)
    fi
}

if [ "${1:-}" = "clean" ]; then
    cleanup
    echo "==> Done (clean only)."
    exit 0
fi

echo "==> Killing running MuH…"
pkill -x MuH 2>/dev/null || true
sleep 0.5

echo "==> Regenerating Xcode project (XcodeGen)…"
xcodegen generate >/dev/null

echo "==> Building Release…"
xcodebuild -project MuH.xcodeproj -scheme MuH -configuration Release \
    -derivedDataPath ./build/DerivedData build 2>&1 | tail -3

APP="./build/DerivedData/Build/Products/Release/MuH.app"
if [ ! -d "$APP" ]; then
    echo "!! Release MuH.app not found after build" >&2
    exit 1
fi

echo "==> Installing to /Applications…"
rm -rf /Applications/MuH.app
cp -R "$APP" /Applications/MuH.app
find /Applications/MuH.app -type d -exec chmod 755 {} +
find /Applications/MuH.app -type f -exec chmod 644 {} +
chmod 755 /Applications/MuH.app/Contents/MacOS/MuH
for setup in setup-herdr.sh setup-luvus.sh; do
    if [ -f "/Applications/MuH.app/Contents/Resources/$setup" ]; then
        chmod 755 "/Applications/MuH.app/Contents/Resources/$setup"
    fi
done

# Install first, cleanup after — cleanup only touches copies outside /Applications.
cleanup

# Force-register the fresh official bundle.
if [ -x "$LSREG" ]; then
    "$LSREG" -f /Applications/MuH.app >/dev/null 2>&1 || true
fi

echo "==> Launching /Applications/MuH.app…"
open /Applications/MuH.app
sleep 0.5
pgrep -x MuH >/dev/null || echo "!! launch failed"
echo "==> Done."
