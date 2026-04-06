#!/bin/zsh

set -euo pipefail

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

mkdir -p "$ROOT/Scripts"
mkdir -p "$ROOT/fake-bin"
mkdir -p "$ROOT/home/Applications"
mkdir -p "$ROOT/Applications"
mkdir -p "$ROOT/private/tmp/MarkdownQuickLookApp.app/Contents"
mkdir -p "$ROOT/private/tmp/Other.app/Contents"
mkdir -p "$ROOT/Library/Developer/Xcode/DerivedData/Build/Products/Debug/MarkdownQuickLook.app/Contents"

cp "$REPO_ROOT/Scripts/uninstall-markdown-quicklook.sh" "$ROOT/Scripts/uninstall-markdown-quicklook.sh"

cat > "$ROOT/home/Applications/MarkdownQuickLook.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.rzkr.MarkdownQuickLook.app</string>
</dict>
</plist>
PLIST

cat > "$ROOT/private/tmp/MarkdownQuickLookApp.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.MarkdownQuickLook.app</string>
</dict>
</plist>
PLIST

cat > "$ROOT/Library/Developer/Xcode/DerivedData/Build/Products/Debug/MarkdownQuickLook.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.rzkr.MarkdownQuickLook.app</string>
</dict>
</plist>
PLIST

cat > "$ROOT/private/tmp/Other.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.OtherApp</string>
</dict>
</plist>
PLIST

cat > "$ROOT/fake-bin/pluginkit" <<'SH'
#!/bin/zsh
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_LOG"
if [[ "$1" == "-mDvvv" ]]; then
  cat <<EOF
+    plugin: com.rzkr.MarkdownQuickLook.app.preview
        Path = $TEST_ROOT/home/Applications/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex
        Path = $TEST_ROOT/private/tmp/MarkdownQuickLookApp.app/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex
+    plugin: com.example.MarkdownQuickLook.app.preview
        Path = $TEST_ROOT/Library/Developer/Xcode/DerivedData/Build/Products/Debug/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex
EOF
fi
SH
chmod +x "$ROOT/fake-bin/pluginkit"

cat > "$ROOT/fake-bin/qlmanage" <<'SH'
#!/bin/zsh
set -euo pipefail
printf 'qlmanage %s\n' "$*" >> "$TEST_LOG"
SH
chmod +x "$ROOT/fake-bin/qlmanage"

export HOME="$ROOT/home"
export TEST_ROOT="$ROOT"
export TEST_LOG="$ROOT/commands.log"
export PATH="$ROOT/fake-bin:/usr/bin:/bin:/usr/sbin:/sbin"

pushd "$ROOT" >/dev/null
if zsh Scripts/uninstall-markdown-quicklook.sh >"$ROOT/output.txt" 2>"$ROOT/error.txt"; then
  echo "expected uninstall script to fail before implementation exists"
  exit 1
fi
popd >/dev/null

if ! grep -q "No such file or directory" "$ROOT/error.txt"; then
  echo "expected missing script error"
  cat "$ROOT/error.txt"
  exit 1
fi

echo "red phase passed: uninstall script is not implemented yet"
