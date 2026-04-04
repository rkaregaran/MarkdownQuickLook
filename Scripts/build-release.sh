#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH="$ROOT/.derivedData/release-build"
DIST_DIR="$ROOT/dist"
APP_NAME="MarkdownQuickLook.app"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME"
DIST_APP_PATH="$DIST_DIR/$APP_NAME"
LICENSE_PATH="$ROOT/LICENSE"
DIST_LICENSE_PATH="$DIST_DIR/LICENSE"
ARCHIVE_DIR="$DIST_DIR/archive-root"
ZIP_PATH="$DIST_DIR/MarkdownQuickLook-macOS.zip"

xcodegen generate

rm -rf "$DIST_DIR" "$DERIVED_DATA_PATH"
mkdir -p "$DIST_DIR"

signing_args=()
if [[ "${CI:-}" == "true" ]]; then
  if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
    signing_args=(
      CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY"
      CODE_SIGN_STYLE=Manual
    )
  else
    signing_args=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=)
  fi
fi

xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLookApp \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${signing_args[@]}" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

ditto "$APP_PATH" "$DIST_APP_PATH"
cp "$LICENSE_PATH" "$DIST_LICENSE_PATH"

"$ROOT/Scripts/check-preview-runtime.sh" "$DIST_APP_PATH"

rm -rf "$ARCHIVE_DIR"
mkdir -p "$ARCHIVE_DIR"
ditto "$DIST_APP_PATH" "$ARCHIVE_DIR/$APP_NAME"
cp "$DIST_LICENSE_PATH" "$ARCHIVE_DIR/LICENSE"
ditto -c -k --sequesterRsrc "$ARCHIVE_DIR" "$ZIP_PATH"
rm -rf "$ARCHIVE_DIR"

echo "App path: $DIST_APP_PATH"
echo "License path: $DIST_LICENSE_PATH"
echo "Zip path: $ZIP_PATH"
echo "SHA-256:"
shasum -a 256 "$ZIP_PATH"
