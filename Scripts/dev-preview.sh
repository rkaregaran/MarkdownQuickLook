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

APP_PATH="$ROOT/.derivedData/Build/Products/Debug/MarkdownQuickLook.app"

"$ROOT/Scripts/check-preview-runtime.sh" "$APP_PATH"

open "$APP_PATH"

sleep 2
qlmanage -r
qlmanage -r cache

echo
echo "Extension registration:"
if command -v rg >/dev/null 2>&1; then
  REGISTRATION_OUTPUT="$(pluginkit -m -A | rg 'MarkdownQuickLook' || true)"
else
  REGISTRATION_OUTPUT="$(pluginkit -m -A | grep 'MarkdownQuickLook' || true)"
fi
if [[ -n "$REGISTRATION_OUTPUT" ]]; then
  echo "$REGISTRATION_OUTPUT"
else
  echo "  Warning: no MarkdownQuickLook registration entries were found."
fi

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
