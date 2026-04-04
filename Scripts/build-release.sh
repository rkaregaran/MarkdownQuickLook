#!/bin/zsh
set -euo pipefail

NOTARIZE=false
if [[ "${1:-}" == "--notarize" ]]; then
  NOTARIZE=true
fi

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

signing_args=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=)
if [[ "${CI:-}" != "true" ]]; then
  signing_args=()
  if [[ "$NOTARIZE" == "true" && -z "${DEVELOPER_ID_IDENTITY:-}" ]]; then
    DEVELOPER_ID_IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    if [[ -z "$DEVELOPER_ID_IDENTITY" ]]; then
      echo "Error: --notarize requires a Developer ID Application certificate in your keychain"
      exit 1
    fi
    echo "Found: $DEVELOPER_ID_IDENTITY"
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

# Re-sign with Developer ID if available (CI with certificate).
if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
  echo "Re-signing with: $DEVELOPER_ID_IDENTITY"

  # Sign the extension first, then the app (inside-out).
  EXTENSION_PATH="$DIST_APP_PATH/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex"
  codesign --force --sign "$DEVELOPER_ID_IDENTITY" \
    --entitlements "$ROOT/MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements" \
    --options runtime \
    "$EXTENSION_PATH"

  codesign --force --sign "$DEVELOPER_ID_IDENTITY" \
    --entitlements "$ROOT/MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements" \
    --options runtime \
    "$DIST_APP_PATH"
fi
cp "$LICENSE_PATH" "$DIST_LICENSE_PATH"

"$ROOT/Scripts/check-preview-runtime.sh" "$DIST_APP_PATH"

rm -rf "$ARCHIVE_DIR"
mkdir -p "$ARCHIVE_DIR"
ditto "$DIST_APP_PATH" "$ARCHIVE_DIR/$APP_NAME"
cp "$DIST_LICENSE_PATH" "$ARCHIVE_DIR/LICENSE"
ditto -c -k --sequesterRsrc "$ARCHIVE_DIR" "$ZIP_PATH"
rm -rf "$ARCHIVE_DIR"

if [[ "$NOTARIZE" == "true" && -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
  "$ROOT/Scripts/notarize.sh" "$ZIP_PATH"
fi

echo "App path: $DIST_APP_PATH"
echo "License path: $DIST_LICENSE_PATH"
echo "Zip path: $ZIP_PATH"
echo "SHA-256:"
shasum -a 256 "$ZIP_PATH"
