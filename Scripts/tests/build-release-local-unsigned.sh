#!/bin/zsh
set -euo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

ROOT="$TEST_DIR/repo"
BIN_DIR="$TEST_DIR/bin"
LOG_PATH="$TEST_DIR/xcodebuild-args.log"
CODE_SIGN_LOG="$TEST_DIR/codesign-args.log"

mkdir -p "$ROOT/Scripts" "$ROOT/dist" "$BIN_DIR"
cp /Users/reza.karegaran/Code/quicklook-md/Scripts/build-release.sh "$ROOT/Scripts/build-release.sh"
chmod +x "$ROOT/Scripts/build-release.sh"

cat > "$ROOT/Scripts/check-preview-runtime.sh" <<'EOF'
#!/bin/zsh
set -euo pipefail
exit 0
EOF
chmod +x "$ROOT/Scripts/check-preview-runtime.sh"

cat > "$ROOT/LICENSE" <<'EOF'
MIT License
EOF

cat > "$BIN_DIR/xcodegen" <<'EOF'
#!/bin/zsh
set -euo pipefail
exit 0
EOF
chmod +x "$BIN_DIR/xcodegen"

cat > "$BIN_DIR/xcodebuild" <<EOF
#!/bin/zsh
set -euo pipefail
printf '%s\n' "\$@" > "$LOG_PATH"
derived_data=""
args=( "\$@" )
for ((i = 1; i <= \$#args; i++)); do
  if [[ "\${args[i]}" == "-derivedDataPath" ]]; then
    derived_data="\${args[i+1]}"
    break
  fi
done
if [[ -z "\$derived_data" ]]; then
  echo "missing -derivedDataPath" >&2
  exit 1
fi
mkdir -p "\$derived_data/Build/Products/Release/MarkdownQuickLook.app"
mkdir -p "\$derived_data/Build/Products/Release/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex"
mkdir -p "\$derived_data/Build/Products/Release/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookThumbnailExtension.appex"
exit 0
EOF
chmod +x "$BIN_DIR/xcodebuild"

cat > "$BIN_DIR/ditto" <<'EOF'
#!/bin/zsh
set -euo pipefail
if [[ "$1" == "-c" ]]; then
  touch "$5"
else
  src="$1"
  dst="$2"
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
fi
EOF
chmod +x "$BIN_DIR/ditto"

cat > "$BIN_DIR/shasum" <<'EOF'
#!/bin/zsh
set -euo pipefail
echo "fake-sha  $2"
EOF
chmod +x "$BIN_DIR/shasum"

cat > "$BIN_DIR/codesign" <<EOF
#!/bin/zsh
set -euo pipefail
printf '%s\n' "\$*" >> "$CODE_SIGN_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/codesign"

PATH="$BIN_DIR:/bin:/usr/bin" "$ROOT/Scripts/build-release.sh" >/dev/null

if ! grep -qx 'CODE_SIGN_IDENTITY=-' "$LOG_PATH"; then
  echo "Expected local build-release invocation to pass CODE_SIGN_IDENTITY=- to xcodebuild" >&2
  exit 1
fi

if ! grep -qx 'CODE_SIGNING_REQUIRED=NO' "$LOG_PATH"; then
  echo "Expected local build-release invocation to pass CODE_SIGNING_REQUIRED=NO to xcodebuild" >&2
  exit 1
fi

if ! grep -qx 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO' "$LOG_PATH"; then
  echo "Expected local build-release invocation to pass CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO to xcodebuild" >&2
  exit 1
fi

if ! grep -q -- '--force --sign - --entitlements .*/MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements .*/dist/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex' "$CODE_SIGN_LOG"; then
  echo "Expected local build-release invocation to ad-hoc re-sign the preview extension with entitlements" >&2
  cat "$CODE_SIGN_LOG" >&2
  exit 1
fi

if ! grep -q -- '--force --sign - --entitlements .*/MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements .*/dist/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookThumbnailExtension.appex' "$CODE_SIGN_LOG"; then
  echo "Expected local build-release invocation to ad-hoc re-sign the thumbnail extension with entitlements" >&2
  cat "$CODE_SIGN_LOG" >&2
  exit 1
fi

if ! grep -q -- '--force --sign - --entitlements .*/MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements .*/dist/MarkdownQuickLook.app' "$CODE_SIGN_LOG"; then
  echo "Expected local build-release invocation to ad-hoc re-sign the app with entitlements" >&2
  cat "$CODE_SIGN_LOG" >&2
  exit 1
fi

echo "build-release local unsigned signing test passed"
