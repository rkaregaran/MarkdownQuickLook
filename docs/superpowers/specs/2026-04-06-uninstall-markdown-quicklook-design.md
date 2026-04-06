# Uninstall Script Design

## Summary

Add a standalone shell script that fully removes MarkdownQuickLook from a Mac by unregistering its Quick Look extensions, deleting old app bundles from common locations, and resetting Quick Look caches.

This script is intentionally destructive when run. It does not prompt for confirmation or offer a dry-run mode.

## Requirements

- Add a script at `Scripts/uninstall-markdown-quicklook.sh`
- Unregister stale Quick Look extension copies for MarkdownQuickLook
- Remove installed or built `MarkdownQuickLook.app` bundles from common locations
- Match app bundles by bundle identifier, not only by filename
- Support both current and legacy bundle identifiers
- Reset Quick Look caches after cleanup
- Print a clear summary of what was removed and what was not found
- Add at least one automated shell regression test for bundle matching / deletion behavior

## Architecture

### Extension cleanup

The script will target only MarkdownQuickLook extension bundle identifiers:

- `com.rzkr.MarkdownQuickLook.app.preview`
- `com.rzkr.MarkdownQuickLook.app.thumbnail`
- `com.example.MarkdownQuickLook.app.preview`

For each identifier, the script will inspect PlugInKit registration output and parse registered extension paths. Any matching registered path will be unregistered with `pluginkit -r <path>`.

This mirrors the existing host-app cleanup logic, but makes it runnable independently when the app itself is broken or when multiple stale registrations exist.

### App bundle cleanup

The script will search a bounded set of common locations where stale builds or installs are likely to exist:

- `/Applications`
- `~/Applications`
- repo-local `.derivedData`
- `~/Library/Developer/Xcode/DerivedData`
- `/tmp`
- `/private/tmp`

It will look for `MarkdownQuickLook.app` and then validate each candidate by reading its `CFBundleIdentifier` from `Contents/Info.plist`.

Accepted app bundle identifiers:

- `com.rzkr.MarkdownQuickLook.app`
- `com.example.MarkdownQuickLook.app`

Only candidates with one of those bundle identifiers will be deleted. This avoids deleting unrelated apps that happen to share the same filename.

Deletion uses `rm -rf` on the validated `.app` bundle path.

### Cache reset

After unregistering extensions and deleting app bundles, the script will run:

- `qlmanage -r`
- `qlmanage -r cache`

This ensures Finder and Quick Look do not keep stale registration state.

### Output contract

The script prints flat, readable sections:

- registered extensions removed
- app bundles deleted
- app bundles skipped because identifiers did not match
- nothing-found cases
- cache reset completion

The script exits successfully when cleanup completes, even if nothing was found to remove.

## Files Changed

| File | Change |
|------|--------|
| `Scripts/uninstall-markdown-quicklook.sh` | New cleanup script |
| `Scripts/tests/uninstall-markdown-quicklook.sh` | New shell regression test |
| `README.md` | Add uninstall instructions |

## Test Strategy

Add a shell test that stages fake app bundles in a temp directory:

- one `MarkdownQuickLook.app` with a matching bundle identifier
- one `MarkdownQuickLook.app` with a non-matching bundle identifier

The test verifies:

- matching bundle is deleted
- non-matching bundle is preserved
- cleanup script exits zero

The test should stub destructive or system-global commands like `pluginkit` and `qlmanage` so it can run safely in automation.

## Out of Scope

- Interactive confirmation prompts
- Dry-run mode
- Removing unrelated Quick Look extensions
- Cleaning arbitrary user-selected directories outside the fixed search list
- Uninstalling notarization credentials, keychains, or developer certificates
