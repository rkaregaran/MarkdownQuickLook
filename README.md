# Markdown Quick Look

Markdown Quick Look is a macOS Quick Look app for previewing standard Markdown files in Finder.

It is best effort for regular `.md` files, which means Finder may not always pick it over the built-in plain-text preview.

## Install

1. Download `MarkdownQuickLook-macOS.zip` from GitHub Releases.
2. Unzip it.
3. Drag `MarkdownQuickLook.app` into `/Applications`.
4. Control-click the app and choose `Open` the first time, because the app is unsigned.
5. Launch it once, then click `Close App`.

## Use

1. Select a `.md` file in Finder.
2. Press `Space`.

## Important Caveat

Finder may still prefer Apple's built-in plain-text preview on some macOS versions.

## Development

Requirements:

- Xcode 26.1.1 or newer
- XcodeGen 2.45.3 or newer

Generate and open the project:

```bash
xcodegen generate
open MarkdownQuickLook.xcodeproj
```

Run the local preview flow:

```bash
./Scripts/dev-preview.sh
```

Build a release package:

```bash
./Scripts/build-release.sh
```
