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
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

ditto "$APP_PATH" "$DIST_APP_PATH"

EXTENSION_DIR="$DIST_APP_PATH/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex/Contents/MacOS"
EXTENSION_BINARY="$EXTENSION_DIR/MarkdownQuickLookPreviewExtension"
EXTENSION_DEBUG_BINARY="$EXTENSION_DIR/MarkdownQuickLookPreviewExtension.debug.dylib"

if [[ -f "$EXTENSION_BINARY" && ! -f "$EXTENSION_DEBUG_BINARY" ]]; then
  cp "$EXTENSION_BINARY" "$EXTENSION_DEBUG_BINARY"
  TEMP_DEBUG_EXTENSION_CREATED=1
else
  TEMP_DEBUG_EXTENSION_CREATED=0
fi

"$ROOT/Scripts/check-preview-runtime.sh" "$DIST_APP_PATH"

if [[ "$TEMP_DEBUG_EXTENSION_CREATED" -eq 1 ]]; then
  rm -f "$EXTENSION_DEBUG_BINARY"
fi

ditto -c -k --keepParent "$DIST_APP_PATH" "$ZIP_PATH"

echo "App path: $DIST_APP_PATH"
echo "Zip path: $ZIP_PATH"
echo "SHA-256:"
shasum -a 256 "$ZIP_PATH"
