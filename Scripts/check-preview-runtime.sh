#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [app-path]"
  exit 1
fi

if [[ $# -eq 1 ]]; then
  APP_PATH="$1"
else
  DERIVED_DATA_PATH="$ROOT/.derivedData/runtime-check"
  APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/MarkdownQuickLook.app"

  xcodegen generate

  xcodebuild \
    -project MarkdownQuickLook.xcodeproj \
    -scheme MarkdownQuickLookApp \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build >/dev/null
fi

EXTENSION_DIR="$APP_PATH/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex/Contents/MacOS"
EXTENSION_BINARY="$EXTENSION_DIR/MarkdownQuickLookPreviewExtension"
EXTENSION_DEBUG_BINARY="$EXTENSION_DIR/MarkdownQuickLookPreviewExtension.debug.dylib"
EXTENSION_FRAMEWORK="$APP_PATH/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex/Contents/Frameworks/MarkdownRendering.framework"
APP_FRAMEWORK="$APP_PATH/Contents/Frameworks/MarkdownRendering.framework"

if [[ ! -f "$EXTENSION_BINARY" ]]; then
  echo "Expected preview extension binary at:"
  echo "  $EXTENSION_BINARY"
  exit 1
fi

EXTENSION_PATH="$EXTENSION_BINARY"
DEPENDENCIES="$(otool -L "$EXTENSION_PATH")"

if [[ "$DEPENDENCIES" == *"MarkdownQuickLookPreviewExtension.debug.dylib"* ]]; then
  if [[ ! -f "$EXTENSION_DEBUG_BINARY" ]]; then
    echo "Expected preview extension debug shim at:"
    echo "  $EXTENSION_DEBUG_BINARY"
    exit 1
  fi

  EXTENSION_PATH="$EXTENSION_DEBUG_BINARY"
  DEPENDENCIES="$(otool -L "$EXTENSION_PATH")"
fi

if [[ "$DEPENDENCIES" == *"@rpath/MarkdownRendering.framework/Versions/A/MarkdownRendering"* ]]; then
  if [[ -d "$EXTENSION_FRAMEWORK" || -d "$APP_FRAMEWORK" ]]; then
    echo "Preview runtime check passed: MarkdownRendering.framework is bundled."
    exit 0
  fi

  echo "Preview runtime check failed: extension links MarkdownRendering.framework but it is not bundled."
  echo
  echo "Checked:"
  echo "  $EXTENSION_FRAMEWORK"
  echo "  $APP_FRAMEWORK"
  exit 1
fi

echo "Preview runtime check passed: extension does not require a bundled MarkdownRendering.framework."
