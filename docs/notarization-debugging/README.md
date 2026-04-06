# Notarization And Release Debugging

This document captures the release-signing failure that caused Markdown Quick Look to install successfully on one Mac, but fail to register its Quick Look extensions and fall back to plain-text previews in Finder.

## What Happened

The repo started on one Mac and later moved to another Mac with the Apple Developer account and notarization setup. After pulling the latest code back onto the original Mac and building locally, the installed app launched but Finder showed plain text for Markdown files.

At first glance this looked like a Quick Look registration issue. It was not.

The real problem was that the Mac was running a locally built ad-hoc app, not the notarized release artifact, and the local release path had stripped entitlements from the packaged app and its embedded extensions.

That meant:

- the app bundle existed and could launch
- the `.appex` bundles were embedded correctly
- `codesign --verify --deep` still reported the bundle as valid on disk
- PlugInKit refused to register the extensions
- Finder fell back to the built-in plain-text preview

## The Key Symptoms

These were the signals that mattered:

- `/Applications/MarkdownQuickLook.app` existed
- `pluginkit -mDvvv -i com.rzkr.MarkdownQuickLook.app.preview` returned `(no matches)`
- the app bundle contained both embedded extensions
- `codesign -dv --verbose=4 /Applications/MarkdownQuickLook.app` showed:
  - `Signature=adhoc`
  - `TeamIdentifier=not set`
- `codesign -d --entitlements :-` on the app and preview extension printed nothing

That last point was the real bug: the local build path produced an ad-hoc signed app with no entitlements.

## Root Cause

The local release script intentionally forced an unsigned build:

```zsh
CODE_SIGN_IDENTITY=-
CODE_SIGNING_REQUIRED=NO
CODE_SIGN_ENTITLEMENTS=
CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
```

That let `xcodebuild` complete on machines without a `Developer ID Application` certificate, but it also removed the app and extension entitlements during the build.

The script only re-signed the app bundle when `DEVELOPER_ID_IDENTITY` was available. On machines without that certificate, the script stopped after packaging and never restored the entitlements with a final ad-hoc signing pass.

So the app was:

- packaged
- launchable
- not notarized
- not entitled correctly for Quick Look registration

## How We Proved It

### 1. Confirmed the installed app was not the notarized artifact

```bash
codesign -dv --verbose=4 /Applications/MarkdownQuickLook.app
```

Important output:

- `Signature=adhoc`
- `TeamIdentifier=not set`

If this is a real notarized GitHub release, you should see a proper Developer ID signature and team identifier instead.

### 2. Confirmed the extensions were missing from PlugInKit

```bash
pluginkit -mDvvv -i com.rzkr.MarkdownQuickLook.app.preview
pluginkit -mDvvv -i com.rzkr.MarkdownQuickLook.app.thumbnail
```

Both returned `(no matches)`.

### 3. Confirmed the app bundle still contained the `.appex` files

```bash
find /Applications/MarkdownQuickLook.app/Contents -maxdepth 3 \
  \( -name '*.appex' -o -name Info.plist \) | sort
```

So the problem was not packaging. It was registration.

### 4. Confirmed entitlements were missing

```bash
codesign -d --entitlements :- /Applications/MarkdownQuickLook.app
codesign -d --entitlements :- \
  /Applications/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex
```

Both printed nothing on the broken local install.

### 5. Proved entitlements were the blocker

Manually re-signing the installed app and both extensions with the real entitlement files caused the preview extension to register immediately:

```bash
codesign --force --sign - \
  --entitlements MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements \
  /Applications/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex

codesign --force --sign - \
  --entitlements MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements \
  /Applications/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookThumbnailExtension.appex

codesign --force --sign - \
  --entitlements MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements \
  /Applications/MarkdownQuickLook.app

open /Applications/MarkdownQuickLook.app
pluginkit -mDvvv -i com.rzkr.MarkdownQuickLook.app.preview
```

After that, PlugInKit showed the preview extension registered from `/Applications/MarkdownQuickLook.app`.

## The Fix

`Scripts/build-release.sh` now always performs a final inside-out signing pass on the packaged app:

- if `DEVELOPER_ID_IDENTITY` is available:
  - sign with Developer ID and `--options runtime`
- otherwise:
  - ad-hoc sign with `-`

In both cases the script re-signs:

1. `MarkdownQuickLookPreviewExtension.appex`
2. `MarkdownQuickLookThumbnailExtension.appex`
3. `MarkdownQuickLook.app`

using the real entitlements from the repo.

This preserves two workflows:

- notarized release builds on the machine or CI that has the Developer ID certificate
- locally installable builds on machines that do not have Developer ID certs

## The Regression Test

The unsigned local build path is covered by:

- [Scripts/tests/build-release-local-unsigned.sh](/Users/reza.karegaran/Code/quicklook-md/Scripts/tests/build-release-local-unsigned.sh)

That test now verifies the local release script:

- still disables Xcode signing during the archive build
- performs an ad-hoc re-sign afterward
- applies the correct entitlement files to the preview extension, thumbnail extension, and app bundle

Run it with:

```bash
zsh Scripts/tests/build-release-local-unsigned.sh
```

## Fast Triage Checklist

If previews suddenly fall back to plain text after installing a local or release build, check these in order:

1. Verify which app you actually installed.
   Use `mdfind "kMDItemCFBundleIdentifier == 'com.rzkr.MarkdownQuickLook.app'"`.
2. Check whether the app is Developer ID signed or ad-hoc.
   Use `codesign -dv --verbose=4 /Applications/MarkdownQuickLook.app`.
3. Check whether the preview extension is registered.
   Use `pluginkit -mDvvv -i com.rzkr.MarkdownQuickLook.app.preview`.
4. Check whether entitlements are present.
   Use `codesign -d --entitlements :-` on the app and the preview extension.
5. If registration is missing but entitlements are present, relaunch the app once from `/Applications`.
6. If the app in `/Applications` is ad-hoc and missing entitlements, rebuild with `./Scripts/build-release.sh` after this fix or install the notarized GitHub Release artifact instead.

## Important Distinction

There were actually two separate classes of build in play:

- proper notarized release artifact
- local fallback release build

The notarized path depends on:

- `Developer ID Application` certificate
- `notarytool` credentials
- `Scripts/notarize.sh`

The local fallback path does not.

The bug only affected the local fallback path on machines without Developer ID signing set up.

## Practical Recommendation

When debugging release installs, do not start with Finder behavior. Start with signing and registration:

1. `codesign -dv --verbose=4 ...`
2. `codesign -d --entitlements :- ...`
3. `pluginkit -mDvvv -i ...`

If those three are wrong, Finder is just the symptom.
