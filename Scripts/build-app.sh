#!/usr/bin/env bash
# Builds build/Clipward.app: a universal (Apple silicon + Intel) binary for macOS 10.13+.
#
# Uses swiftc directly so it works with just the Command Line Tools (no Xcode needed).
# Environment:
#   SIGN_IDENTITY  codesigning identity (default "-" = ad-hoc). Pass a "Developer ID
#                  Application: …" identity to get a hardened-runtime build for distribution.
#   VERSION        bundle version (default 1.0.0)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Clipward.app"
MIN_MACOS="10.13"
VERSION="${VERSION:-1.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

CORE_SOURCES=("$ROOT"/Sources/ClipwardCore/*.swift)
APP_SOURCES=("$ROOT"/Sources/Clipward/*.swift "$ROOT"/Sources/Clipward/UI/*.swift)

build_arch() {
    local arch="$1"
    local target="$arch-apple-macosx$MIN_MACOS"
    local out="$BUILD/$arch"
    mkdir -p "$out"
    echo "==> Compiling for $arch"
    swiftc -O -whole-module-optimization -sdk "$SDK" -target "$target" \
        -parse-as-library -module-name ClipwardCore \
        -emit-library -static -emit-module -emit-module-path "$out/ClipwardCore.swiftmodule" \
        -o "$out/libClipwardCore.a" "${CORE_SOURCES[@]}"
    swiftc -O -whole-module-optimization -sdk "$SDK" -target "$target" \
        -module-name Clipward -I "$out" -L "$out" -lClipwardCore \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
        -o "$out/Clipward" "${APP_SOURCES[@]}"
}

rm -rf "$APP"
build_arch arm64
build_arch x86_64

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
lipo -create -output "$APP/Contents/MacOS/Clipward" "$BUILD/arm64/Clipward" "$BUILD/x86_64/Clipward"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__MIN_MACOS__/$MIN_MACOS/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# macOS before 10.14.4 ships without the Swift runtime, so bundle Apple's back-deployment
# copy. Newer systems load the OS copy first (swiftc puts /usr/lib/swift ahead of our rpath).
TOOLCHAIN_LIBS=""
for candidate in \
    "$(xcode-select -p)/usr/lib/swift-5.0/macosx" \
    "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.0/macosx"; do
    if [ -d "$candidate" ]; then TOOLCHAIN_LIBS="$candidate"; break; fi
done
if [ -n "$TOOLCHAIN_LIBS" ]; then
    # Copy the libraries the binary links, plus their own Swift dependencies.
    pending=$(otool -L "$APP/Contents/MacOS/Clipward" | awk '/@rpath\/libswift/ {print $1}' | sed 's|@rpath/||')
    while [ -n "$pending" ]; do
        next=""
        for lib in $pending; do
            [ -f "$APP/Contents/Frameworks/$lib" ] || [ ! -f "$TOOLCHAIN_LIBS/$lib" ] && continue
            cp "$TOOLCHAIN_LIBS/$lib" "$APP/Contents/Frameworks/"
            next="$next $(otool -L "$TOOLCHAIN_LIBS/$lib" | awk '/@rpath\/libswift/ {print $1}' | sed 's|@rpath/||')"
        done
        pending="$next"
    done
else
    echo "warning: Swift back-deployment libraries not found; the app will need macOS 10.14.4+" >&2
fi

echo "==> Signing ($SIGN_IDENTITY)"
SIGN_FLAGS=(--force --timestamp=none --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then SIGN_FLAGS=(--force --timestamp --options runtime --sign "$SIGN_IDENTITY"); fi
for lib in "$APP"/Contents/Frameworks/*.dylib; do
    [ -e "$lib" ] && codesign "${SIGN_FLAGS[@]}" "$lib" 2>/dev/null
done
codesign "${SIGN_FLAGS[@]}" "$APP" 2>/dev/null
codesign --verify --strict "$APP"

echo "==> Done: $APP"
