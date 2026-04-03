# Markdown Quick Look Release Distribution Design

## Goal

Prepare the project for public distribution as an MIT-licensed macOS app with:

- a host app window that clearly tells the user the Quick Look extension is installed
- an obvious `Close App` action that communicates the app only needs to be launched once
- a reproducible production build that outputs a Release `.app` packaged for GitHub Releases

## Constraints

- Keep the public install flow intentionally simple
- Do not add Developer ID signing, notarization, Sparkle, DMGs, installers, or auto-update infrastructure
- Assume users will drag `MarkdownQuickLook.app` into `/Applications`
- Assume the public GitHub Releases asset is a `.zip` that contains the `.app`
- The first-launch docs must explicitly cover the unsigned-app `Control-click > Open` flow
- The app must continue to frame standard `.md` preview override as best-effort, not guaranteed

## User Flow

The target end-user flow is:

1. Download the release `.zip` from GitHub Releases
2. Unzip it
3. Drag `MarkdownQuickLook.app` into `/Applications`
4. `Control-click` the app and choose `Open` the first time because the app is unsigned
5. Launch the app once to register the embedded Quick Look extension
6. Read the confirmation window
7. Click `Close App`
8. Preview Markdown files in Finder with `Space`

After that first launch, the app does not need to remain open for Quick Look previews to work.

## Product Shape

The project remains a small host app plus embedded Quick Look Preview Extension. This release work does not change the extension model. It adds clearer messaging and a repeatable public artifact.

The release-oriented changes break into three areas:

1. Host app install-confirmation UX
2. Release build and packaging tooling
3. Public-facing repo metadata and documentation

## Host App UX

### Purpose

The host app window should behave like an installation confirmation screen, not a developer dashboard.

### Required Messaging

The window should communicate four points clearly:

- the Markdown Quick Look extension is installed
- Finder can now try to use the app for Markdown preview
- the app only needed to be launched once after being moved to `/Applications`
- the user can close the app now and does not need to reopen it for normal use

### Layout Direction

The window should be visually decisive and confidence-building:

- a strong success-style headline near the top
- short explanatory copy beneath it
- a short “How to use it” section
- a large primary button labeled `Close App`
- optional supporting secondary text for caveats

The current developer-oriented content such as fixture instructions and opened-file diagnostics should be removed from the default release window.

### Caveat Placement

The best-effort `.md` takeover caveat should remain visible, but it should not dominate the screen. It belongs in secondary copy that says some macOS versions may still prefer the built-in plain-text preview for standard Markdown files.

### Button Behavior

`Close App` should terminate the host app immediately. The wording should reinforce that this is the expected end state, not an interruption.

## Release Build and Packaging

### Artifact Shape

The release process should produce:

- a Release-built `MarkdownQuickLook.app`
- a zipped artifact suitable for GitHub Releases upload

The zip should unpack directly to `MarkdownQuickLook.app`, not to a deeply nested folder structure.

### Build Script

Add a release packaging script, expected at `Scripts/build-release.sh`, that:

1. runs `xcodegen generate`
2. builds the app in `Release` configuration
3. stages the built app into a clean distribution directory
4. creates a zip artifact for GitHub Releases
5. prints the final artifact paths

The script should prefer deterministic local output under a repo-owned directory such as `dist/` instead of leaving release assets hidden inside DerivedData.

### Output Conventions

The script should generate a predictable artifact name so release uploads are obvious. A simple stable name is sufficient, for example:

- `dist/MarkdownQuickLook.app`
- `dist/MarkdownQuickLook-macOS.zip`

Versioned asset naming is out of scope for this phase.

### Scope Limits

The production build flow should stay unsigned and unnotarized. The goal is reproducible packaging, not App Store or hardened runtime distribution.

## Repo and Docs

### License

Add an MIT `LICENSE` file at the repo root.

### README

Rewrite `README.md` around public distribution rather than local development.

The README should lead with:

- what the app does
- the best-effort limitation for standard `.md`
- install steps from GitHub Releases
- drag-to-`/Applications` guidance
- unsigned-app first-launch instructions using `Control-click > Open`
- “launch once, then close it” guidance
- how to preview a Markdown file in Finder

Developer-oriented instructions should remain, but move below the end-user install section. They should cover local verification and local release packaging separately.

### Release Instructions

The repo should make it obvious how maintainers generate the public asset. This can live in the README and in comments or usage output from the release script.

## Verification

### UX Verification

Confirm the host app window:

- clearly states installation is complete
- clearly states the app can be closed now
- offers a visible primary `Close App` button

### Packaging Verification

Confirm the release script produces:

- a Release `MarkdownQuickLook.app`
- a `.zip` that expands to `MarkdownQuickLook.app`

### Behavior Verification

Confirm the existing local preview verification flow still works after the UX and packaging changes.

The two accepted outcomes remain:

- Finder uses the custom Markdown preview
- Finder continues using the built-in plain-text preview even though the app and extension are installed correctly

## Out of Scope

- signing
- notarization
- DMG creation
- auto-update support
- custom installer flows
- guaranteeing override of Apple’s built-in `.md` preview path

## Exit Criteria

This design is complete when:

- the repo includes an MIT license
- the app window reads as a one-time installation confirmation experience
- the app has a prominent `Close App` button that exits the app
- the README supports non-technical end users downloading from GitHub Releases
- a maintainer can run one release script and obtain a GitHub-uploadable zip containing `MarkdownQuickLook.app`
