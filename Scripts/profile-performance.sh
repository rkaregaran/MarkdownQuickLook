#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT/.derivedData/performance-profile"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/MarkdownQuickLook.app"

cd "$ROOT"

xcodegen generate

xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLookApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

"$ROOT/Scripts/check-preview-runtime.sh" "$APP_PATH"

open "$APP_PATH"
sleep 2

pluginkit -e use -i com.rzkr.MarkdownQuickLook.app.preview
pluginkit -e use -i com.rzkr.MarkdownQuickLook.app.thumbnail

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
