#!/usr/bin/env bash
# Compiles ClipwardCore with the test runner in Tests/ and runs it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/tests"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$OUT"

swiftc -sdk "$SDK" -parse-as-library -module-name ClipwardCore \
    -emit-library -static -emit-module -emit-module-path "$OUT/ClipwardCore.swiftmodule" \
    -o "$OUT/libClipwardCore.a" "$ROOT"/Sources/ClipwardCore/*.swift
swiftc -sdk "$SDK" -module-name ClipwardCoreTests -I "$OUT" -L "$OUT" -lClipwardCore \
    -o "$OUT/ClipwardCoreTests" "$ROOT"/Tests/ClipwardCoreTests/*.swift
"$OUT/ClipwardCoreTests"
