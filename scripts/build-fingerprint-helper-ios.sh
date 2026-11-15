#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_DIR="$ROOT_DIR/FingerprintHelper"
OUT_DIR="$HELPER_DIR/build/ios-arm64"
OUT_LIB="$OUT_DIR/libolazfp.a"

mkdir -p "$OUT_DIR"

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG_BIN="$(xcrun --sdk iphoneos --find clang)"

export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
export CGO_ENABLED=1
export GOOS=ios
export GOARCH=arm64
export CC="$CLANG_BIN"
export CGO_CFLAGS="-isysroot $SDK_PATH -arch arm64 -miphoneos-version-min=17.0 -fembed-bitcode=no"
export CGO_LDFLAGS="-isysroot $SDK_PATH -arch arm64 -miphoneos-version-min=17.0"

echo "==> Building FingerprintHelper C-archive (ios/arm64, min iOS 17.0)"
(
  cd "$HELPER_DIR"
  go build -trimpath -ldflags="-s -w" -buildmode=c-archive -o "$OUT_LIB" .
)

ls -lh "$OUT_LIB"
