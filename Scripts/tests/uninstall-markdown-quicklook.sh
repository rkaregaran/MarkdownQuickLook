#!/bin/zsh

set -euo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

ROOT="$TEST_DIR/repo"
BIN_DIR="$TEST_DIR/bin"
LOG_DIR="$TEST_DIR/logs"
HOME_DIR="$TEST_DIR/home"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

mkdir -p "$ROOT/Scripts" "$BIN_DIR" "$LOG_DIR" "$HOME_DIR/Applications" "$HOME_DIR/Applications/Other" "$TEST_DIR/legacy"
cp "$REPO_ROOT/Scripts/uninstall-markdown-quicklook.sh" "$ROOT/Scripts/uninstall-markdown-quicklook.sh"
chmod +x "$ROOT/Scripts/uninstall-markdown-quicklook.sh"

MATCHING_APP="$HOME_DIR/Applications/MarkdownQuickLook.app"
LEGACY_APP="$TEST_DIR/legacy/MarkdownQuickLookApp.app"
SKIPPED_APP="$HOME_DIR/Applications/Other/MarkdownQuickLook.app"

mkdir -p "$MATCHING_APP/Contents" "$LEGACY_APP/Contents" "$SKIPPED_APP/Contents"

cat > "$MATCHING_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.rzkr.MarkdownQuickLook.app</string>
</dict>
</plist>
PLIST

cat > "$LEGACY_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.MarkdownQuickLook.app</string>
</dict>
</plist>
PLIST

cat > "$SKIPPED_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.SomeOtherApp</string>
</dict>
</plist>
PLIST

cat > "$BIN_DIR/pluginkit" <<EOF
#!/bin/zsh
set -euo pipefail
printf '%s\n' "\$*" >> "$LOG_DIR/pluginkit.log"
if [[ "\$1" == "-mDvvv" ]]; then
  case "\$3" in
    com.rzkr.MarkdownQuickLook.app.preview)
      cat <<'OUT'
    Path = /tmp/MarkdownQuickLookPreviewExtension.appex
OUT
      ;;
    com.rzkr.MarkdownQuickLook.app.thumbnail)
      cat <<'OUT'
    Path = /tmp/MarkdownQuickLookThumbnailExtension.appex
OUT
      ;;
    com.example.MarkdownQuickLook.app.preview)
      cat <<'OUT'
    Path = /tmp/LegacyMarkdownQuickLookPreviewExtension.appex
OUT
      ;;
  esac
fi
EOF
chmod +x "$BIN_DIR/pluginkit"

cat > "$BIN_DIR/qlmanage" <<EOF
#!/bin/zsh
set -euo pipefail
printf '%s\n' "\$*" >> "$LOG_DIR/qlmanage.log"
EOF
chmod +x "$BIN_DIR/qlmanage"

HOME="$HOME_DIR" \
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
MARKDOWN_QUICKLOOK_SEARCH_ROOTS="$HOME_DIR:$HOME_DIR/Applications:$TEST_DIR/legacy" \
zsh "$ROOT/Scripts/uninstall-markdown-quicklook.sh" > "$LOG_DIR/output.log"

if [[ -d "$MATCHING_APP" ]]; then
  echo "Expected matching MarkdownQuickLook.app bundle to be deleted" >&2
  exit 1
fi

if [[ -d "$LEGACY_APP" ]]; then
  echo "Expected matching legacy MarkdownQuickLookApp.app bundle to be deleted" >&2
  exit 1
fi

if [[ ! -d "$SKIPPED_APP" ]]; then
  echo "Expected non-matching MarkdownQuickLook.app bundle to be preserved" >&2
  exit 1
fi

if ! grep -q -- "-r /tmp/MarkdownQuickLookPreviewExtension.appex" "$LOG_DIR/pluginkit.log"; then
  echo "Expected preview extension removal command" >&2
  exit 1
fi

if ! grep -q -- "-r /tmp/MarkdownQuickLookThumbnailExtension.appex" "$LOG_DIR/pluginkit.log"; then
  echo "Expected thumbnail extension removal command" >&2
  exit 1
fi

if ! grep -q -- "-r /tmp/LegacyMarkdownQuickLookPreviewExtension.appex" "$LOG_DIR/pluginkit.log"; then
  echo "Expected legacy preview extension removal command" >&2
  exit 1
fi

if ! grep -q -- "^-r$" "$LOG_DIR/qlmanage.log"; then
  echo "Expected qlmanage reset command" >&2
  exit 1
fi

if ! grep -q -- "^-r cache$" "$LOG_DIR/qlmanage.log"; then
  echo "Expected qlmanage cache reset command" >&2
  exit 1
fi

if [[ "$(grep -Fc -- "$SKIPPED_APP" "$LOG_DIR/output.log")" -ne 1 ]]; then
  echo "Expected skipped app bundle to appear once in output summary" >&2
  cat "$LOG_DIR/output.log"
  exit 1
fi

if ! grep -Fq -- "$MATCHING_APP" "$LOG_DIR/output.log"; then
  echo "Expected removed app bundle to appear in output summary" >&2
  exit 1
fi

if ! grep -Fq -- "$LEGACY_APP" "$LOG_DIR/output.log"; then
  echo "Expected removed legacy app bundle to appear in output summary" >&2
  exit 1
fi

echo "uninstall-markdown-quicklook test passed"
