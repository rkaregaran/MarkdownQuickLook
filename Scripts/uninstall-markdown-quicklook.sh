#!/bin/zsh

set -euo pipefail

extension_ids=(
  "com.rzkr.MarkdownQuickLook.app.preview"
  "com.rzkr.MarkdownQuickLook.app.thumbnail"
  "com.example.MarkdownQuickLook.app.preview"
)

app_bundle_ids=(
  "com.rzkr.MarkdownQuickLook.app"
  "com.example.MarkdownQuickLook.app"
)

app_names=(
  "MarkdownQuickLook.app"
  "MarkdownQuickLookApp.app"
)

search_roots=()
if [[ -n "${MARKDOWN_QUICKLOOK_SEARCH_ROOTS:-}" ]]; then
  IFS=':' read -rA search_roots <<< "${MARKDOWN_QUICKLOOK_SEARCH_ROOTS}"
else
  search_roots=(
    "/Applications"
    "$HOME/Applications"
    "$(cd "$(dirname "$0")/.." && pwd)/.derivedData"
    "$HOME/Library/Developer/Xcode/DerivedData"
    "/tmp"
    "/private/tmp"
  )
fi

removed_extensions=()
removed_apps=()
skipped_apps=()
seen_app_paths=()

contains_value() {
  local needle="$1"
  shift
  local item

  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

plist_bundle_id() {
  local app_path="$1"
  local plist_path="$app_path/Contents/Info.plist"

  [[ -f "$plist_path" ]] || return 1
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist_path" 2>/dev/null
}

find_registered_paths() {
  local extension_id="$1"
  local output
  local line

  output="$(pluginkit -mDvvv -i "$extension_id" 2>/dev/null || true)"

  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" == Path\ =\ * ]] || continue
    print -r -- "${line#Path = }"
  done <<< "$output"
}

for extension_id in "${extension_ids[@]}"; do
  while IFS= read -r extension_path; do
    [[ -n "$extension_path" ]] || continue
    pluginkit -r "$extension_path" >/dev/null 2>&1 || true
    removed_extensions+=("$extension_path")
  done < <(find_registered_paths "$extension_id")
done

for root in "${search_roots[@]}"; do
  [[ -d "$root" ]] || continue

  for app_name in "${app_names[@]}"; do
    while IFS= read -r app_path; do
      local_bundle_id=""

      [[ -n "$app_path" ]] || continue
      if contains_value "$app_path" "${seen_app_paths[@]}"; then
        continue
      fi
      seen_app_paths+=("$app_path")

      local_bundle_id="$(plist_bundle_id "$app_path" || true)"
      if contains_value "$local_bundle_id" "${app_bundle_ids[@]}"; then
        rm -rf "$app_path"
        removed_apps+=("$app_path")
      else
        skipped_apps+=("$app_path")
      fi
    done < <(find "$root" -type d -name "$app_name" 2>/dev/null)
  done
done

qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "Removed extensions:"
if [[ ${#removed_extensions[@]} -eq 0 ]]; then
  echo "  none"
else
  printf '  %s\n' "${removed_extensions[@]}"
fi

echo
echo "Removed app bundles:"
if [[ ${#removed_apps[@]} -eq 0 ]]; then
  echo "  none"
else
  printf '  %s\n' "${removed_apps[@]}"
fi

echo
echo "Skipped app bundles:"
if [[ ${#skipped_apps[@]} -eq 0 ]]; then
  echo "  none"
else
  printf '  %s\n' "${skipped_apps[@]}"
fi

echo
echo "Quick Look caches reset."
