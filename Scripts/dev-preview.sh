#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLookApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/.derivedData" \
  build

APP_PATH="$ROOT/.derivedData/Build/Products/Debug/MarkdownQuickLookApp.app"

open "$APP_PATH"

sleep 2
qlmanage -r
qlmanage -r cache

echo
echo "Extension registration:"
pluginkit -m -A | rg 'MarkdownQuickLook' || true

echo
echo "App bundle:"
echo "  $APP_PATH"

echo
echo "Fixture:"
echo "  $ROOT/Fixtures/Sample.md"

echo
echo "Next steps:"
echo "  1. Open Finder."
echo "  2. Select the fixture file."
echo "  3. Press Space."
echo
echo "If Finder still shows plain text, the extension built correctly but macOS kept the built-in preview path."
