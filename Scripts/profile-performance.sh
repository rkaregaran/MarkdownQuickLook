#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT/.derivedData/performance-profile"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/MarkdownQuickLook.app"
PREVIEW_EXTENSION_PATH="$APP_PATH/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex"
THUMBNAIL_EXTENSION_PATH="$APP_PATH/Contents/PlugIns/MarkdownQuickLookThumbnailExtension.appex"
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
  sign_if_present "$APP_PATH/Contents/MacOS/MarkdownQuickLook.debug.dylib"
  sign_if_present "$APP_PATH/Contents/MacOS/__preview.dylib"
  sign_if_present "$PREVIEW_EXTENSION_PATH/Contents/MacOS/MarkdownQuickLookPreviewExtension.debug.dylib"
  sign_if_present "$PREVIEW_EXTENSION_PATH/Contents/MacOS/__preview.dylib"
  sign_if_present "$THUMBNAIL_EXTENSION_PATH/Contents/MacOS/MarkdownQuickLookThumbnailExtension.debug.dylib"
  sign_if_present "$THUMBNAIL_EXTENSION_PATH/Contents/MacOS/__preview.dylib"

  /usr/bin/codesign \
    --force \
    --sign - \
    --entitlements "$ROOT/MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements" \
    --timestamp=none \
    "$PREVIEW_EXTENSION_PATH"

  /usr/bin/codesign \
    --force \
    --sign - \
    --entitlements "$ROOT/MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements" \
    --timestamp=none \
    "$THUMBNAIL_EXTENSION_PATH"

  /usr/bin/codesign \
    --force \
    --sign - \
    --entitlements "$ROOT/MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements" \
    --timestamp=none \
    "$APP_PATH"

  /usr/bin/codesign --verify --deep --strict "$APP_PATH"
}

register_local_extensions() {
  pluginkit -a "$PREVIEW_EXTENSION_PATH" "$THUMBNAIL_EXTENSION_PATH"
}

remove_stale_extension_registrations() {
  remove_stale_extension_registration "$PREVIEW_EXTENSION_ID" "$PREVIEW_EXTENSION_PATH"
  remove_stale_extension_registration "$THUMBNAIL_EXTENSION_ID" "$THUMBNAIL_EXTENSION_PATH"
}

remove_stale_extension_registration() {
  local extension_id="$1"
  local expected_path="$2"
  local registrations
  local line
  local plugin_path

  registrations="$(pluginkit -m -D -v -i "$extension_id" || true)"

  while IFS= read -r line; do
    [[ "$line" == *"$extension_id"* ]] || continue
    plugin_path="${line##*$'\t'}"
    [[ "$plugin_path" == "$expected_path" ]] && continue
    [[ "$plugin_path" == /*.appex ]] || continue

    pluginkit -r "$plugin_path" || true
  done <<< "$registrations"
}

verify_extension_registration() {
  local preview_registration
  local thumbnail_registration

  preview_registration="$(pluginkit -m -v -i "$PREVIEW_EXTENSION_ID" || true)"
  thumbnail_registration="$(pluginkit -m -v -i "$THUMBNAIL_EXTENSION_ID" || true)"

  if [[ "$preview_registration" != *"$PREVIEW_EXTENSION_ID"* ]] ||
    [[ "$preview_registration" != *"$PREVIEW_EXTENSION_PATH"* ]] ||
    [[ "$thumbnail_registration" != *"$THUMBNAIL_EXTENSION_ID"* ]] ||
    [[ "$thumbnail_registration" != *"$THUMBNAIL_EXTENSION_PATH"* ]]; then
    echo "PlugInKit did not register both local MarkdownQuickLook extensions." >&2
    echo "Expected:" >&2
    echo "  $PREVIEW_EXTENSION_ID at $PREVIEW_EXTENSION_PATH" >&2
    echo "  $THUMBNAIL_EXTENSION_ID at $THUMBNAIL_EXTENSION_PATH" >&2
    echo "Observed:" >&2
    if [[ -n "$preview_registration" ]] || [[ -n "$thumbnail_registration" ]]; then
      {
        echo "$preview_registration"
        echo "$thumbnail_registration"
      } | sed '/^$/d; s/^/  /' >&2
    else
      echo "  <none>" >&2
    fi
    exit 1
  fi

  echo
  echo "Extension registration:"
  {
    echo "$preview_registration"
    echo "$thumbnail_registration"
  } | sed '/^$/d; s/^/  /'
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

remove_stale_extension_registrations
register_local_extensions
open "$APP_PATH"
sleep 2

pluginkit -e use -i "$PREVIEW_EXTENSION_ID"
pluginkit -e use -i "$THUMBNAIL_EXTENSION_ID"
remove_stale_extension_registrations
register_local_extensions
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
