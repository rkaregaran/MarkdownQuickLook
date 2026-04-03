# Markdown Quick Look

[![Release Workflow](https://img.shields.io/github/actions/workflow/status/rkaregaran/MarkdownQuickLook/release.yml?label=release%20workflow)](https://github.com/rkaregaran/MarkdownQuickLook/actions/workflows/release.yml)
[![Download Latest Release](https://img.shields.io/badge/download-latest%20release-2ea44f)](https://github.com/rkaregaran/MarkdownQuickLook/releases/latest)
[![Latest Release Date](https://img.shields.io/github/release-date/rkaregaran/MarkdownQuickLook)](https://github.com/rkaregaran/MarkdownQuickLook/releases/latest)
[![License: MIT](https://img.shields.io/github/license/rkaregaran/MarkdownQuickLook)](https://github.com/rkaregaran/MarkdownQuickLook/blob/main/LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-1f6feb)](https://github.com/rkaregaran/MarkdownQuickLook#install)

Markdown Quick Look is a macOS Quick Look app for previewing standard Markdown files in Finder.
It requires macOS 14.0 or newer.

It is best effort for regular `.md` files, which means Finder may not always pick it over the built-in plain-text preview.

## Install

[Download latest release](https://github.com/rkaregaran/MarkdownQuickLook/releases/latest)

**Important:** macOS will block this app because it is unsigned and may tell you to move it to Trash. After you try to open `MarkdownQuickLook.app` once, open `System Settings` > `Privacy & Security`, explicitly allow the app there, and then open it again from `/Applications`.

1. Download `MarkdownQuickLook-macOS.zip` from GitHub Releases.
2. Unzip it.
3. Drag `MarkdownQuickLook.app` into `/Applications`.
4. Try to open `MarkdownQuickLook.app` once from `/Applications`.
5. If macOS blocks it or tells you to move it to Trash, open `System Settings` > `Privacy & Security` and explicitly allow `MarkdownQuickLook.app`.
6. Open `MarkdownQuickLook.app` again from `/Applications`, then click `Close App`. You should not need to open it again after that first successful launch.

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

## Automated Releases

Every push to `main` creates a new rolling GitHub release through GitHub Actions.
Each release uploads `MarkdownQuickLook-macOS.zip`, which expands to `MarkdownQuickLook.app` and `LICENSE`.

Local release packaging is still available with:

```bash
./Scripts/build-release.sh
```
