#!/usr/bin/env bash
# Packages build/Clipward.app into build/Clipward-<version>.dmg with a drag-to-Applications layout.
# Requires Python 3; dmgbuild is installed into build/.venv on first run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Clipward.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="$BUILD/Clipward-$VERSION.dmg"
WORK="$BUILD/dmg"

[ -d "$APP" ] || { echo "error: $APP not found; run Scripts/build-app.sh first" >&2; exit 1; }

if [ ! -x "$BUILD/.venv/bin/dmgbuild" ]; then
    python3 -m venv "$BUILD/.venv"
    "$BUILD/.venv/bin/pip" install --quiet "dmgbuild==1.6.1"
fi

echo "==> Drawing background"
mkdir -p "$WORK"
swiftc "$ROOT/Scripts/dmg/make-background.swift" -o "$WORK/make-background"
"$WORK/make-background" "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null

echo "==> Building $DMG"
rm -f "$DMG"
"$BUILD/.venv/bin/dmgbuild" -s "$ROOT/Scripts/dmg/settings.py" \
    -D app="$APP" -D background="$WORK/background.tiff" "Clipward" "$DMG"

if [ "${SIGN_IDENTITY:--}" != "-" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
(cd "$BUILD" && shasum -a 256 "$(basename "$DMG")") | tee "$DMG.sha256"
echo "==> Done: $DMG"
