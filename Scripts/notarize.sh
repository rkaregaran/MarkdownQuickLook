#!/bin/zsh
set -euo pipefail

# Usage: notarize.sh <zip-path>
#
# Credentials (two modes):
#   1. Keychain profile: store credentials once with
#      xcrun notarytool store-credentials "MarkdownQuickLook" \
#        --key <p8-file> --key-id <key-id> --issuer <issuer-id>
#   2. Env vars: NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER_ID (used by CI)
#
# The zip must contain a single .app at its root.

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <zip-path>"
  exit 1
fi

ZIP_PATH="$1"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Determine credential args: env vars (CI) or keychain profile (local).
NOTARY_ARGS=()
if [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  KEY_FILE="$WORK_DIR/notary-key.p8"
  echo "$NOTARY_KEY" > "$KEY_FILE"
  NOTARY_ARGS=(--key "$KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
elif xcrun notarytool history --keychain-profile "MarkdownQuickLook" > /dev/null 2>&1; then
  NOTARY_ARGS=(--keychain-profile "MarkdownQuickLook")
else
  echo "Error: No notarization credentials found."
  echo "Either set NOTARY_KEY/NOTARY_KEY_ID/NOTARY_ISSUER_ID env vars,"
  echo "or store credentials with:"
  echo "  xcrun notarytool store-credentials \"MarkdownQuickLook\" \\"
  echo "    --key <p8-file> --key-id <key-id> --issuer <issuer-id>"
  exit 1
fi

echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" "${NOTARY_ARGS[@]}" --wait

# Extract the app for stapling.
STAPLE_DIR="$WORK_DIR/staple"
mkdir -p "$STAPLE_DIR"
ditto -x -k "$ZIP_PATH" "$STAPLE_DIR"

APP_PATH="$(find "$STAPLE_DIR" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Error: no .app found in zip"
  exit 1
fi

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

# Re-zip with the stapled app, replacing the original zip.
ARCHIVE_DIR="$WORK_DIR/archive"
mkdir -p "$ARCHIVE_DIR"
ditto "$APP_PATH" "$ARCHIVE_DIR/$(basename "$APP_PATH")"

# Preserve LICENSE if present in original zip.
LICENSE_PATH="$(find "$STAPLE_DIR" -maxdepth 1 -name 'LICENSE' -print -quit)"
if [[ -n "$LICENSE_PATH" ]]; then
  cp "$LICENSE_PATH" "$ARCHIVE_DIR/LICENSE"
fi

ditto -c -k --sequesterRsrc "$ARCHIVE_DIR" "$ZIP_PATH"

echo "Notarization complete."
