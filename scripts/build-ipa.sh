#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUNTIME_DIR="$ROOT_DIR/build/ZaloRuntime"
DERIVED_DIR="$ROOT_DIR/build/DerivedDataIOS"
STAGE_DIR="$ROOT_DIR/build/ipa-stage"
DIST_DIR="$ROOT_DIR/dist"
UNSIGNED_IPA="$DIST_DIR/Olaz-iOS-unsigned.ipa"

echo "==> 1/6 Generating 1024x1024 RGB iOS AppIcon"
python3 scripts/generate-ios-icon.py

echo "==> 2/6 Building Go FingerprintHelper C-archive (ios/arm64)"
bash scripts/build-fingerprint-helper-ios.sh

echo "==> 3/6 Preparing pre-bundled ZaloRuntime (app.asar 26.10.20)"
if [[ "${FORCE_RUNTIME_REFRESH:-0}" == "1" || ! -f "$RUNTIME_DIR/Contents/Resources/app.asar" ]]; then
  python3 scripts/prepare-ios-runtime.py --out "$RUNTIME_DIR"
else
  echo "Reusing existing $RUNTIME_DIR"
fi

echo "==> 4/6 Generating Xcode project via XcodeGen"
xcodegen generate --spec "$ROOT_DIR/project.yml"

echo "==> 5/6 Building Olaz.app (Release, iphoneos/arm64, unsigned)"
rm -rf "$DERIVED_DIR"
xcodebuild \
  -project "$ROOT_DIR/OlazIOS.xcodeproj" \
  -scheme Olaz \
  -configuration Release \
  -sdk iphoneos \
  -arch arm64 \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$DERIVED_DIR/Build/Products/Release-iphoneos/Olaz.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Built Olaz.app not found at $APP_PATH" >&2
  exit 1
fi
if [[ ! -f "$APP_PATH/ZaloRuntime/Contents/Resources/app.asar" ]]; then
  echo "ERROR: Pre-bundled ZaloRuntime/Contents/Resources/app.asar missing from Olaz.app!" >&2
  exit 1
fi

echo "==> 6/6 Packaging dist/Olaz-iOS-unsigned.ipa"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Payload" "$DIST_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/Payload/Olaz.app"
xattr -cr "$STAGE_DIR/Payload/Olaz.app" 2>/dev/null || true

codesign --force --sign - \
  --entitlements "$ROOT_DIR/scripts/OlazIOS.entitlements" \
  --timestamp=none \
  "$STAGE_DIR/Payload/Olaz.app"

rm -f "$UNSIGNED_IPA"
(
  cd "$STAGE_DIR"
  zip -qry -X "$UNSIGNED_IPA" Payload
)

ls -lh "$UNSIGNED_IPA"

DEFAULT_CERT_DIR="$ROOT_DIR/build/certs/00008020-001474A40A81002E"
HAS_EXPLICIT_CERT=0
HAS_LOCAL_CERT=0
if [[ -n "${MUACERT_P12_PATH:-}" && -n "${MUACERT_PROVISION_PATH:-}" ]]; then
  HAS_EXPLICIT_CERT=1
elif [[ -f "$DEFAULT_CERT_DIR/cert.p12" && -f "$DEFAULT_CERT_DIR/cert.mobileprovision" ]]; then
  HAS_LOCAL_CERT=1
fi

if [[ "$HAS_EXPLICIT_CERT" == "1" || "$HAS_LOCAL_CERT" == "1" ]]; then
  if command -v zsign >/dev/null 2>&1; then
    DIST_DIR="$DIST_DIR" UNSIGNED_IPA="$UNSIGNED_IPA" bash "$ROOT_DIR/scripts/sign-ipa.sh"
  else
    echo "NOTE: zsign not found; skipping optional local muacert signing."
  fi
fi
