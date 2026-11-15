#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
UNSIGNED_IPA="${UNSIGNED_IPA:-$DIST_DIR/Olaz-iOS-unsigned.ipa}"
SIGNED_IPA="${SIGNED_IPA:-$DIST_DIR/Olaz-iOS-signed.ipa}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-Olaz}"
DEFAULT_CERT_DIR="$ROOT_DIR/build/certs/00008020-001474A40A81002E"

P12_PATH="${MUACERT_P12_PATH:-}"
PROV_PATH="${MUACERT_PROVISION_PATH:-}"
P12_PASS="${MUACERT_P12_PASSWORD:-}"

if [[ -z "$P12_PATH" && -z "$PROV_PATH" && -f "$DEFAULT_CERT_DIR/cert.p12" && -f "$DEFAULT_CERT_DIR/cert.mobileprovision" ]]; then
  P12_PATH="$DEFAULT_CERT_DIR/cert.p12"
  PROV_PATH="$DEFAULT_CERT_DIR/cert.mobileprovision"
  if [[ -z "$P12_PASS" && -f "$DEFAULT_CERT_DIR/pass.txt" ]]; then
    P12_PASS="$(tr -d '\r\n' < "$DEFAULT_CERT_DIR/pass.txt")"
  fi
  echo "Auto-detected local certificate in $DEFAULT_CERT_DIR"
fi

if [[ -z "$P12_PATH" || -z "$PROV_PATH" ]]; then
  echo "ERROR: MUACERT_P12_PATH and MUACERT_PROVISION_PATH must be set (or place cert.p12 + cert.mobileprovision in $DEFAULT_CERT_DIR)." >&2
  exit 1
fi
if [[ ! -f "$P12_PATH" ]]; then
  echo "ERROR: Certificate file not found: $P12_PATH" >&2
  exit 1
fi
if [[ ! -f "$PROV_PATH" ]]; then
  echo "ERROR: Provisioning profile not found: $PROV_PATH" >&2
  exit 1
fi
if [[ ! -f "$UNSIGNED_IPA" ]]; then
  echo "ERROR: Unsigned IPA not found: $UNSIGNED_IPA" >&2
  exit 1
fi
if ! command -v zsign >/dev/null 2>&1; then
  echo "ERROR: zsign is required to sign the IPA (install via: brew install zsign)." >&2
  exit 1
fi

SIGN_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/olaz-sign.XXXXXX")"
trap 'rm -rf "$SIGN_WORK_DIR"' EXIT

PREP_ARGS=(
  --provision "$PROV_PATH"
  --p12 "$P12_PATH"
  --password "$P12_PASS"
  --entitlements-out "$SIGN_WORK_DIR/signed.entitlements"
  --bundle-id-out "$SIGN_WORK_DIR/bundle_id.txt"
)
if [[ -n "${EXPECT_UDID:-}" ]]; then
  PREP_ARGS+=(--expect-udid "$EXPECT_UDID")
fi

python3 "$ROOT_DIR/scripts/prepare-signing-profile.py" "${PREP_ARGS[@]}"
TARGET_BUNDLE_ID="$(tr -d '\r\n' < "$SIGN_WORK_DIR/bundle_id.txt")"

mkdir -p "$(dirname "$SIGNED_IPA")"
rm -f "$SIGNED_IPA"

echo "==> Signing $UNSIGNED_IPA -> $SIGNED_IPA (bundle_id=$TARGET_BUNDLE_ID, name=$APP_DISPLAY_NAME)"
zsign \
  -k "$P12_PATH" \
  -p "$P12_PASS" \
  -m "$PROV_PATH" \
  -b "$TARGET_BUNDLE_ID" \
  -n "$APP_DISPLAY_NAME" \
  -e "$SIGN_WORK_DIR/signed.entitlements" \
  -z 9 \
  -o "$SIGNED_IPA" \
  "$UNSIGNED_IPA"

VERIFY_ARGS=(
  --verify-ipa "$SIGNED_IPA"
  --expected-bundle-id "$TARGET_BUNDLE_ID"
)
if [[ -n "${EXPECT_UDID:-}" ]]; then
  VERIFY_ARGS+=(--expect-udid "$EXPECT_UDID")
fi

python3 "$ROOT_DIR/scripts/prepare-signing-profile.py" "${VERIFY_ARGS[@]}"
if [[ "$(uname -s)" == "Darwin" ]] && command -v codesign >/dev/null 2>&1; then
  ditto -x -k "$SIGNED_IPA" "$SIGN_WORK_DIR/verify_signed"
  codesign --verify --deep --strict --verbose=2 "$SIGN_WORK_DIR/verify_signed/Payload/Olaz.app"
fi
ls -lh "$SIGNED_IPA"
