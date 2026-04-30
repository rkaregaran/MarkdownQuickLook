#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT/.derivedData/performance-profile"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/MarkdownQuickLook.app"
PREVIEW_EXTENSION_ID="com.rzkr.MarkdownQuickLook.app.preview"
THUMBNAIL_EXTENSION_ID="com.rzkr.MarkdownQuickLook.app.thumbnail"

cd "$ROOT"

sign_if_present() {
  local path="$1"

  if [[ -e "$path" ]]; then
    /usr/bin/codesign --force --sign - --timestamp=none "$path"
  fi
}

sign_local_profiling_app() {
  local preview_appex="$APP_PATH/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex"
  local thumbnail_appex="$APP_PATH/Contents/PlugIns/MarkdownQuickLookThumbnailExtension.appex"

  sign_if_present "$APP_PATH/Contents/MacOS/MarkdownQuickLook.debug.dylib"
  sign_if_present "$APP_PATH/Contents/MacOS/__preview.dylib"
  sign_if_present "$preview_appex/Contents/MacOS/MarkdownQuickLookPreviewExtension.debug.dylib"
  sign_if_present "$preview_appex/Contents/MacOS/__preview.dylib"
  sign_if_present "$thumbnail_appex/Contents/MacOS/MarkdownQuickLookThumbnailExtension.debug.dylib"
  sign_if_present "$thumbnail_appex/Contents/MacOS/__preview.dylib"

  /usr/bin/codesign \
    --force \
    --sign - \
    --entitlements "$ROOT/MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements" \
    --timestamp=none \
    "$preview_appex"

  /usr/bin/codesign \
    --force \
    --sign - \
    --entitlements "$ROOT/MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements" \
    --timestamp=none \
    "$thumbnail_appex"

  /usr/bin/codesign \
    --force \
    --sign - \
    --entitlements "$ROOT/MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements" \
    --timestamp=none \
    "$APP_PATH"

  /usr/bin/codesign --verify --deep --strict "$APP_PATH"
}

verify_extension_registration() {
  local registration_output

  registration_output="$(pluginkit -m -A | grep -F 'com.rzkr.MarkdownQuickLook.app.' || true)"

  if [[ "$registration_output" != *"$PREVIEW_EXTENSION_ID"* ]] ||
    [[ "$registration_output" != *"$THUMBNAIL_EXTENSION_ID"* ]]; then
    echo "PlugInKit did not register both MarkdownQuickLook extensions." >&2
    echo "Expected:" >&2
    echo "  $PREVIEW_EXTENSION_ID" >&2
    echo "  $THUMBNAIL_EXTENSION_ID" >&2
    echo "Observed:" >&2
    if [[ -n "$registration_output" ]]; then
      echo "$registration_output" | sed 's/^/  /' >&2
    else
      echo "  <none>" >&2
    fi
    exit 1
  fi

  echo
  echo "Extension registration:"
  echo "$registration_output" | sed 's/^/  /'
}

xcodegen generate

xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLookApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

sign_local_profiling_app

"$ROOT/Scripts/check-preview-runtime.sh" "$APP_PATH"

open "$APP_PATH"
sleep 2

pluginkit -e use -i "$PREVIEW_EXTENSION_ID"
pluginkit -e use -i "$THUMBNAIL_EXTENSION_ID"
verify_extension_registration

qlmanage -r
qlmanage -r cache

echo
echo "Performance profiling build is ready."
echo
echo "App bundle:"
echo "  $APP_PATH"
echo
echo "Performance fixtures:"
find "$ROOT/Fixtures/Performance" -type f -name '*.md' | sort | sed 's/^/  /'
echo
echo "Suggested Instruments workflow:"
echo "  1. Open Instruments and choose Points of Interest or Time Profiler."
echo "  2. Target the Quick Look preview or thumbnail extension process."
echo "  3. Select a fixture in Finder from the list above, then press Space."
echo "  4. Record the preview or thumbnail interaction and inspect signposts."
echo
echo "Instrumentation subsystem:"
echo "  com.rzkr.MarkdownQuickLook"
echo
echo "Primary signposts:"
echo "  preview.request"
echo "  preview.prepare"
echo "  preview.settings"
echo "  preview.render"
echo "  preview.applyView"
echo "  renderer.prepareDocument"
echo "  renderer.renderDocument"
echo "  thumbnail.request"
echo "  thumbnail.prepare"
echo "  thumbnail.render"
echo "  thumbnail.draw"
