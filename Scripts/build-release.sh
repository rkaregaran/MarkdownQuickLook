#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH="$ROOT/.derivedData/release-build"
DIST_DIR="$ROOT/dist"
APP_NAME="MarkdownQuickLook.app"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME"
DIST_APP_PATH="$DIST_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/MarkdownQuickLook-macOS.zip"

xcodegen generate

rm -rf "$DIST_DIR" "$DERIVED_DATA_PATH"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLookApp \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

ditto "$APP_PATH" "$DIST_APP_PATH"

"$ROOT/Scripts/check-preview-runtime.sh" "$DIST_APP_PATH"

ditto -c -k --keepParent "$DIST_APP_PATH" "$ZIP_PATH"

echo "App path: $DIST_APP_PATH"
echo "Zip path: $ZIP_PATH"
echo "SHA-256:"
shasum -a 256 "$ZIP_PATH"
