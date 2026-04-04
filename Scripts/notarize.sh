#!/bin/zsh
set -euo pipefail

# Usage: notarize.sh <zip-path>
# Required env vars: NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER_ID
# The zip must contain a single .app at its root.

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <zip-path>"
  exit 1
fi

ZIP_PATH="$1"

for var in NOTARY_KEY NOTARY_KEY_ID NOTARY_ISSUER_ID; do
  if [[ -z "${(P)var:-}" ]]; then
    echo "Error: $var is not set"
    exit 1
  fi
done

WORK_DIR="$(mktemp -d)"
KEY_FILE="$WORK_DIR/notary-key.p8"
trap 'rm -rf "$WORK_DIR"' EXIT

# Write the API key to a temp file.
echo "$NOTARY_KEY" > "$KEY_FILE"

echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --key "$KEY_FILE" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait

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
