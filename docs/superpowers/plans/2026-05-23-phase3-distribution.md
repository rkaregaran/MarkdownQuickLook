# Phase 3: Distribution & Ops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a real Mac app distribution surface. Replace zip with a signed/notarized DMG, integrate Sparkle for auto-updates, publish a Homebrew cask, adopt Keep-a-Changelog, and switch from rolling releases to tag-driven versioned releases.

**Architecture:** All work lives outside the app source — in `Scripts/`, `.github/workflows/`, the repo root (`CHANGELOG.md`), and a new `appcast.xml` published to a stable URL. The only in-app code change is wiring Sparkle into the host app's lifecycle.

**Tech Stack:** `xcrun notarytool`, `xcrun stapler`, `create-dmg` (or `hdiutil`), GitHub Actions, Sparkle 2.x (Swift Package Manager), Homebrew cask DSL, `awk`/`sed` for changelog parsing.

**Spec:** `docs/superpowers/specs/2026-05-23-pluk-gap-roadmap-design.md` § Phase 3.

**Sequencing note:** Tasks 1 (changelog), 2 (versioned releases), 3 (DMG) are prerequisites for Task 4 (Sparkle) and Task 5 (Homebrew). Do them in order.

---

### Task 1: Adopt `CHANGELOG.md` (Keep-a-Changelog)

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Generate retroactive entries from `git log`**

```bash
git log --oneline --since="2026-04-01" main | head -40
```

This gives you the recent commit list. Group by release tag if any, otherwise group into "Unreleased" + the last 3–5 logical releases.

- [ ] **Step 2: Create `CHANGELOG.md` in Keep-a-Changelog format**

```markdown
# Changelog

All notable changes to MarkdownQuickLook will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (in progress) GitHub-style alert blockquotes.

## [0.X.Y] – 2026-05-23

### Added
- TOC sidebar in Quick Look preview with scrollspy.
- (retroactive entries — fill in based on `git log` summary)

### Changed
- (…)

### Fixed
- (…)
```

(Adjust the version number to whatever `Scripts/build-release.sh` is currently emitting; if the project hasn't versioned before, start at `0.1.0`.)

- [ ] **Step 3: Document the changelog discipline in `CLAUDE.md`**

Append a short section to `CLAUDE.md`:

```markdown
## Changelog discipline

- Every user-visible change adds a bullet to `CHANGELOG.md` under `[Unreleased]`.
- Before tagging a release, move `[Unreleased]` content under the new version heading.
- `Scripts/build-release.sh --version X.Y.Z` validates that a matching entry exists.
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md CLAUDE.md
git commit -m "docs: adopt Keep-a-Changelog format"
```

---

### Task 2: Switch from rolling to tag-driven releases

**Files:**
- Modify: `.github/workflows/release.yml`
- Create: `.github/workflows/ci.yml`
- Modify: `Scripts/build-release.sh`

The current setup releases on every push to `main`. Replace with: pushes to `main` run tests only; tags `v*` run the full release.

- [ ] **Step 1: Read the existing workflow**

```bash
cat .github/workflows/release.yml | head -120
```

Identify:
- What triggers it (`on:` block).
- What it does (build, test, package, release).

- [ ] **Step 2: Split into CI vs Release**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Generate project
        run: xcodegen generate
      - name: Test rendering
        run: xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
      - name: Test preview extension
        run: xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
      - name: Test app
        run: xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

- [ ] **Step 3: Update `release.yml` to trigger only on tags**

Change the trigger:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'
  workflow_dispatch:
```

Remove the rolling timestamp+SHA tag logic. Use `github.ref_name` (which will be the actual tag like `v0.2.0`) as the release version.

- [ ] **Step 4: Parse changelog into release notes**

Add a step to the release workflow that extracts the relevant changelog section:

```yaml
      - name: Extract changelog entry
        id: changelog
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          NOTES=$(awk -v ver="## [$VERSION]" '
            $0 ~ ver { flag=1; next }
            /^## \[/ && flag { exit }
            flag { print }
          ' CHANGELOG.md)
          if [ -z "$NOTES" ]; then
            echo "::error::No CHANGELOG.md entry for $VERSION"
            exit 1
          fi
          echo "notes<<EOF" >> "$GITHUB_OUTPUT"
          echo "$NOTES" >> "$GITHUB_OUTPUT"
          echo "EOF" >> "$GITHUB_OUTPUT"
```

Pass `${{ steps.changelog.outputs.notes }}` into the GitHub release body.

- [ ] **Step 5: Update `Scripts/build-release.sh` to accept `--version`**

Read the existing script:

```bash
cat Scripts/build-release.sh
```

Add argument parsing at the top:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        *) echo "unknown arg: $1"; exit 1 ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0-dev")
fi

# Validate that CHANGELOG.md contains an entry for VERSION (skip for *-dev versions).
if [[ "$VERSION" != *-dev ]]; then
    if ! grep -q "^## \[$VERSION\]" CHANGELOG.md; then
        echo "::error::No CHANGELOG.md entry for $VERSION"
        exit 1
    fi
fi
```

- [ ] **Step 6: Add a `Scripts/cut-release.sh` helper**

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="$1"
[ -z "$VERSION" ] && { echo "usage: cut-release.sh X.Y.Z"; exit 1; }

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "::error::version must be semver X.Y.Z"
    exit 1
fi

if ! grep -q "^## \[$VERSION\]" CHANGELOG.md; then
    echo "::error::No CHANGELOG.md entry for $VERSION (add one before tagging)"
    exit 1
fi

git tag "v$VERSION"
git push origin "v$VERSION"
echo "Tagged v$VERSION. The Release workflow will pick it up on GitHub."
```

`chmod +x Scripts/cut-release.sh`.

- [ ] **Step 7: Run a dry test**

Push the branch (NOT a tag). CI should fire and run only the test workflow. Confirm `release.yml` does not fire.

- [ ] **Step 8: Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/release.yml Scripts/build-release.sh Scripts/cut-release.sh
git commit -m "ci: split CI from release; tag-driven versioned releases"
```

---

### Task 3: Switch artifact from `.zip` to `.dmg`

**Files:**
- Modify: `Scripts/build-release.sh`
- Create: `Scripts/make-dmg.sh`
- Optionally create: `Scripts/dmg-background.png`

- [ ] **Step 1: Install `create-dmg`**

```bash
brew install create-dmg
```

(Or use `hdiutil` directly — slightly more verbose but no extra dep.)

- [ ] **Step 2: Create `Scripts/make-dmg.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_PATH="$1"  # e.g., dist/MarkdownQuickLook.app
DMG_PATH="$2"  # e.g., dist/MarkdownQuickLook.dmg
VERSION="${3:-}"

VOLNAME="MarkdownQuickLook"
if [ -n "$VERSION" ]; then VOLNAME="MarkdownQuickLook $VERSION"; fi

rm -f "$DMG_PATH"

# Optional background image: Scripts/dmg-background.png (540x380 recommended).
BACKGROUND_ARG=""
if [ -f "Scripts/dmg-background.png" ]; then
    BACKGROUND_ARG="--background Scripts/dmg-background.png"
fi

create-dmg \
    --volname "$VOLNAME" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 96 \
    --icon "$(basename "$APP_PATH")" 130 200 \
    --hide-extension "$(basename "$APP_PATH")" \
    --app-drop-link 410 200 \
    $BACKGROUND_ARG \
    "$DMG_PATH" \
    "$APP_PATH"

echo "Created $DMG_PATH"
```

`chmod +x Scripts/make-dmg.sh`.

- [ ] **Step 3: Wire DMG into `Scripts/build-release.sh`**

After the existing build + sign + notarize steps for the `.app`, REPLACE the zip step with:

```bash
# Make DMG.
./Scripts/make-dmg.sh "dist/MarkdownQuickLook.app" "dist/MarkdownQuickLook-${VERSION}.dmg" "$VERSION"

# Sign the DMG with the same Developer ID identity.
codesign --sign "$CODESIGN_IDENTITY" --timestamp --options runtime "dist/MarkdownQuickLook-${VERSION}.dmg"

# Notarize the DMG.
xcrun notarytool submit "dist/MarkdownQuickLook-${VERSION}.dmg" \
    --key "$AUTHKEY_PATH" \
    --key-id "$AUTHKEY_ID" \
    --issuer "$AUTHKEY_ISSUER" \
    --wait

# Staple the notarization ticket onto the DMG.
xcrun stapler staple "dist/MarkdownQuickLook-${VERSION}.dmg"

# Verify Gatekeeper acceptance.
spctl -a -t open --context context:primary-signature -v "dist/MarkdownQuickLook-${VERSION}.dmg"
xcrun stapler validate "dist/MarkdownQuickLook-${VERSION}.dmg"
```

Adjust environment variable names to match what's already in `release.yml` and the script's preamble.

- [ ] **Step 4: Update `release.yml` to upload the DMG**

Find the `actions/upload-artifact` or `softprops/action-gh-release` step. Replace the zip path with `dist/MarkdownQuickLook-${VERSION}.dmg`.

- [ ] **Step 5: Update README install instructions**

In `README.md`, replace any `unzip` flow with:

```markdown
1. Download `MarkdownQuickLook-X.Y.Z.dmg` from [the Releases page](https://github.com/<user>/MarkdownQuickLook/releases/latest).
2. Open the DMG. Drag MarkdownQuickLook to Applications.
3. Open MarkdownQuickLook once. It registers the Quick Look extension and exits.
4. Try it: in Finder, select a `.md` file and press the spacebar.
```

- [ ] **Step 6: Local dry run**

```bash
./Scripts/build-release.sh --version 0.0.0-dev
# Expect: dist/MarkdownQuickLook-0.0.0-dev.dmg exists, opens, drags to Applications.
open dist/MarkdownQuickLook-0.0.0-dev.dmg
```

- [ ] **Step 7: Commit**

```bash
git add Scripts/make-dmg.sh Scripts/build-release.sh .github/workflows/release.yml README.md
git commit -m "release: package as signed, notarized DMG instead of zip"
```

---

### Task 4: Sparkle auto-update

**Files:**
- Modify: `project.yml` (add Sparkle package dependency)
- Modify: `MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements`
- Modify: `MarkdownQuickLookApp/Info.plist`
- Modify: `MarkdownQuickLookApp/App/MarkdownQuickLookApp.swift`
- Modify: `Scripts/build-release.sh`
- Create: `appcast.xml` (sample; CI writes the real one per release)
- Create: `Scripts/publish-appcast.sh`

- [ ] **Step 1: Generate the EdDSA keypair**

Sparkle ships a `generate_keys` tool. On a developer machine (not CI):

```bash
# Resolve Sparkle once locally so the bin is on disk:
xcodegen generate
xcodebuild -resolvePackageDependencies -project MarkdownQuickLook.xcodeproj
# Then locate generate_keys:
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path '*/Sparkle/bin/generate_keys' | head -1)
"$SPARKLE_BIN"
# It saves the private key in Keychain ("https://sparkle-project.org") and prints the public key.
```

Copy the printed public key. It looks like a base64 string.

- [ ] **Step 2: Add Sparkle as a Swift Package**

Edit `project.yml` to add the Sparkle dependency to `MarkdownQuickLookApp`:

```yaml
  MarkdownQuickLookApp:
    # ...existing config...
    dependencies:
      - target: MarkdownQuickLookPreviewExtension
        embed: true
      - target: MarkdownQuickLookThumbnailExtension
        embed: true
      - target: MarkdownRendering
      - package: Sparkle
        product: Sparkle

packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: 2.6.0
```

- [ ] **Step 3: Add the public key to Info.plist**

In `MarkdownQuickLookApp/Info.plist`, add:

```xml
    <key>SUFeedURL</key>
    <string>https://YOUR-DOMAIN-OR-GH-PAGES/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>YOUR-BASE64-PUBLIC-KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
```

The `SUFeedURL` value should be the stable URL you commit to. If you don't have a domain, use `https://<user>.github.io/MarkdownQuickLook/appcast.xml` and serve via GitHub Pages.

- [ ] **Step 4: Update entitlements (sandbox + XPC)**

In `MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements`, ensure outbound network access for Sparkle:

```xml
    <key>com.apple.security.network.client</key>
    <true/>
```

Sparkle XPC services for sandboxed apps require additional entitlements — refer to Sparkle's "Sandboxing" docs and add as needed (e.g. `com.apple.security.temporary-exception.mach-lookup.global-name` arrays).

- [ ] **Step 5: Wire the updater into `MarkdownQuickLookApp.swift`**

```swift
import SwiftUI
import Sparkle

@main
struct MarkdownQuickLookApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            StatusView()
                .environment(\.sparkleUpdater, updaterController.updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
            }
        }
    }
}

// Custom environment key for hand-off:
private struct SparkleUpdaterKey: EnvironmentKey {
    static let defaultValue: SPUUpdater? = nil
}
extension EnvironmentValues {
    var sparkleUpdater: SPUUpdater? {
        get { self[SparkleUpdaterKey.self] }
        set { self[SparkleUpdaterKey.self] = newValue }
    }
}
```

- [ ] **Step 6: Sign release artifacts with EdDSA**

Sparkle ships `sign_update`. Add to `Scripts/build-release.sh` after the DMG is notarized:

```bash
SIGN_UPDATE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path '*/Sparkle/bin/sign_update' | head -1)
SIGNATURE=$("$SIGN_UPDATE_BIN" "dist/MarkdownQuickLook-${VERSION}.dmg")
# SIGNATURE looks like: sparkle:edSignature="…" length="…"
echo "$SIGNATURE" > "dist/MarkdownQuickLook-${VERSION}.dmg.sig"
```

The private key has to live somewhere CI can reach it. In GitHub Actions, store the key (exported from Keychain) as a repository secret `SPARKLE_PRIVATE_KEY`, write it to a tmp file in the workflow, and pass via `--ed-key-file`. See [Sparkle's CI docs](https://sparkle-project.org/documentation/publishing/).

- [ ] **Step 7: Generate and publish `appcast.xml`**

Sparkle ships `generate_appcast`. Add `Scripts/publish-appcast.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Generates an appcast.xml from dist/ and uploads it to the SUFeedURL location.
APPCAST_DIR="${APPCAST_DIR:-dist}"
GENERATE_APPCAST_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path '*/Sparkle/bin/generate_appcast' | head -1)

"$GENERATE_APPCAST_BIN" \
    --download-url-prefix "https://github.com/<user>/MarkdownQuickLook/releases/download/v${VERSION}/" \
    "$APPCAST_DIR"

# Result is at $APPCAST_DIR/appcast.xml.
# Upload to GH Pages or the configured host — concrete commands depend on host.
```

In CI: after building the DMG, run `generate_appcast`, then either commit `appcast.xml` to the `gh-pages` branch or push to the configured static host.

- [ ] **Step 8: Manual end-to-end test**

1. Build version 0.1.0 with the wiring above. Install it.
2. Tag and build version 0.1.1.
3. Publish the appcast.
4. Open the installed 0.1.0 app, click "Check for Updates…". Sparkle should find 0.1.1 and offer to install.
5. Accept. App relaunches at 0.1.1.

- [ ] **Step 9: Commit**

```bash
git add project.yml MarkdownQuickLookApp/Info.plist MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements MarkdownQuickLookApp/App/MarkdownQuickLookApp.swift Scripts/build-release.sh Scripts/publish-appcast.sh
git commit -m "feat: integrate Sparkle 2.x for EdDSA-signed auto-updates"
```

---

### Task 5: Homebrew cask

**Files:**
- Create: `Casks/markdown-quicklook.rb` (in a separate repo: your homebrew tap)

This task can only happen AFTER Tasks 3 (DMG) and 2 (versioned releases) are merged and a real release exists.

- [ ] **Step 1: Decide cask name and tap**

Options:
- Submit to `homebrew/cask` (mainstream — high friction, requires reviewing maintainers).
- Run your own tap (`<user>/homebrew-tap`) — easier, users install via `brew install --cask <user>/tap/markdown-quicklook`.

Recommend starting with your own tap.

- [ ] **Step 2: Create the tap repo**

```bash
# In a new directory outside this repo:
gh repo create <user>/homebrew-tap --public
git clone git@github.com:<user>/homebrew-tap.git
cd homebrew-tap
mkdir Casks
```

- [ ] **Step 3: Write the cask formula**

`Casks/markdown-quicklook.rb`:

```ruby
cask "markdown-quicklook" do
  version "0.X.Y"
  sha256 "<sha256 of the DMG>"

  url "https://github.com/<user>/MarkdownQuickLook/releases/download/v#{version}/MarkdownQuickLook-#{version}.dmg"
  name "MarkdownQuickLook"
  desc "Quick Look extension for Markdown files"
  homepage "https://github.com/<user>/MarkdownQuickLook"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "MarkdownQuickLook.app"

  zap trash: [
    "~/Library/Containers/com.rzkr.MarkdownQuickLook.app",
    "~/Library/Containers/com.rzkr.MarkdownQuickLook.app.preview",
    "~/Library/Containers/com.rzkr.MarkdownQuickLook.app.thumbnail",
    "~/Library/Preferences/com.rzkr.MarkdownQuickLook.app.plist",
    "~/Library/Group Containers/group.com.rzkr.MarkdownQuickLook"
  ]
end
```

Compute the sha256:

```bash
shasum -a 256 dist/MarkdownQuickLook-0.X.Y.dmg
```

- [ ] **Step 4: Test the cask locally**

```bash
brew tap <user>/tap
brew install --cask <user>/tap/markdown-quicklook
# Verify the app installs to /Applications, opens, Quick Look fires on a .md file.
brew uninstall --cask <user>/tap/markdown-quicklook
```

- [ ] **Step 5: Automate cask updates from CI**

Add a step to `release.yml` that, after a successful tag-driven release, checks out the tap repo and updates the cask's `version` and `sha256`:

```yaml
      - name: Update Homebrew cask
        env:
          TAP_TOKEN: ${{ secrets.TAP_PUSH_TOKEN }}
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          SHA=$(shasum -a 256 "dist/MarkdownQuickLook-${VERSION}.dmg" | awk '{print $1}')
          git clone "https://x-access-token:${TAP_TOKEN}@github.com/<user>/homebrew-tap.git" tap
          cd tap
          sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/markdown-quicklook.rb
          sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" Casks/markdown-quicklook.rb
          git add Casks/markdown-quicklook.rb
          git -c user.email=ci@example.com -c user.name=ci commit -m "Update markdown-quicklook to $VERSION"
          git push
```

`TAP_PUSH_TOKEN` is a fine-scoped PAT with `contents: write` for the tap repo.

- [ ] **Step 6: Update README**

Add to the top of `README.md`:

```markdown
## Install

```sh
brew install --cask <user>/tap/markdown-quicklook
```

Or grab the latest DMG from [Releases](https://github.com/<user>/MarkdownQuickLook/releases).
```

- [ ] **Step 7: Commit (in main repo)**

```bash
git add README.md .github/workflows/release.yml
git commit -m "feat: Homebrew cask install instructions and auto-update in CI"
```

---

## End-of-phase verification

- [ ] **Cut a real test release**

```bash
# Bump CHANGELOG.md with an Unreleased → 0.1.0 promotion + entries.
./Scripts/cut-release.sh 0.1.0
# Watch the Release workflow.
gh run watch
```

- [ ] **Validate the artifact chain**

After workflow completes:

```bash
# DMG download
gh release download v0.1.0 -p '*.dmg'
# Gatekeeper
spctl -a -t open --context context:primary-signature -v MarkdownQuickLook-0.1.0.dmg
# Stapled
xcrun stapler validate MarkdownQuickLook-0.1.0.dmg
# Sparkle signature
cat MarkdownQuickLook-0.1.0.dmg.sig
```

- [ ] **Update test**

Install 0.1.0 manually. Cut 0.1.1 (any tiny CHANGELOG-eligible change). Confirm:
- Tag + push fires the release workflow.
- Sparkle "Check for Updates…" finds 0.1.1.
- After install, app version is 0.1.1.
- `brew upgrade --cask <user>/tap/markdown-quicklook` brings 0.1.1.

- [ ] **Document the release flow in `CLAUDE.md`**

```markdown
## Releasing

```bash
# 1. Move [Unreleased] entries in CHANGELOG.md under a new ## [X.Y.Z] heading.
# 2. Commit the changelog change.
# 3. Cut the tag:
./Scripts/cut-release.sh X.Y.Z
# 4. CI builds the DMG, notarizes, publishes the GH release, signs Sparkle
#    payload, updates the appcast, and updates the Homebrew cask.
```

## Out-of-scope reminders

- Mac App Store distribution: would require a separate spec, different signing flow, and removal of Sparkle (MAS auto-updates handle that). Not needed.
- Custom domain for appcast (instead of GH Pages): a nice polish, not blocking.
- Notarization debugging: see `docs/notarization-debugging/README.md` if anything goes wrong with `notarytool`.
- TestFlight: irrelevant for non-MAS apps.
