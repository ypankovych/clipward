#!/usr/bin/env bash
# Regenerates docs/screenshots/*.png from the real UI with demo data.
# Nothing is shown on screen and the clipboard is not touched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/screenshots"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$OUT"

swiftc -sdk "$SDK" -parse-as-library -module-name ClipwardCore \
    -emit-library -static -emit-module -emit-module-path "$OUT/ClipwardCore.swiftmodule" \
    -o "$OUT/libClipwardCore.a" "$ROOT"/Sources/ClipwardCore/*.swift

APP_SOURCES=()
for file in "$ROOT"/Sources/Clipward/*.swift "$ROOT"/Sources/Clipward/UI/*.swift; do
    [ "$(basename "$file")" = "main.swift" ] || APP_SOURCES+=("$file")
done
swiftc -sdk "$SDK" -module-name ClipwardScreenshots -I "$OUT" -L "$OUT" -lClipwardCore \
    -o "$OUT/screenshots" "${APP_SOURCES[@]}" "$ROOT/Scripts/screenshots/main.swift"

"$OUT/screenshots" "$ROOT/docs/screenshots"
