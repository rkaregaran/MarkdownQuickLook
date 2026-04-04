# Notarization & Dual Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notarize GitHub release builds so users never see Gatekeeper warnings or App Data Protection dialogs, then restore settings sharing between the host app and Quick Look extension.

**Architecture:** CI workflow splits into `test` and `release` jobs. The release job imports a Developer ID certificate, builds with it, notarizes via `notarytool`, staples the ticket, and publishes. A new `notarize.sh` script encapsulates the Apple notarization API interaction. Once verified, app group entitlements and settings sharing are restored.

**Tech Stack:** GitHub Actions, Xcode codesigning, `xcrun notarytool`, `xcrun stapler`, zsh scripts.

---

### Task 1: Update `build-release.sh` with three-mode signing

**Files:**
- Modify: `Scripts/build-release.sh`

- [ ] **Step 1: Replace the signing logic in `build-release.sh`**

Replace the current `signing_args` block and xcodebuild invocation with three-mode detection:

```zsh
signing_args=()
if [[ "${CI:-}" == "true" ]]; then
  if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
    signing_args=(
      CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY"
      CODE_SIGN_STYLE=Manual
    )
  else
    signing_args=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=)
  fi
fi
```

The xcodebuild invocation stays the same — it already uses `"${signing_args[@]}"` and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`.

- [ ] **Step 2: Test locally (no env vars set)**

Run:
```bash
./Scripts/build-release.sh
```
Expected: `** BUILD SUCCEEDED **` — uses your development certificate from project.yml as before.

- [ ] **Step 3: Test ad-hoc fallback**

Run:
```bash
CI=true ./Scripts/build-release.sh
```
Expected: `** BUILD SUCCEEDED **` — builds with ad-hoc signing (same as fork CI).

- [ ] **Step 4: Test Developer ID mode**

Run:
```bash
CI=true DEVELOPER_ID_IDENTITY="Developer ID Application: Reza KAREGARAN (42QK7B5HYB)" ./Scripts/build-release.sh
```
Expected: `** BUILD SUCCEEDED **`. Verify signing:
```bash
codesign -dvv dist/MarkdownQuickLook.app 2>&1 | grep "Authority"
```
Expected output includes: `Authority=Developer ID Application: Reza KAREGARAN (42QK7B5HYB)`

- [ ] **Step 5: Commit**

```bash
git add Scripts/build-release.sh
git commit -m "feat: add three-mode signing to build-release script

Local dev uses automatic signing from project.yml, CI with
DEVELOPER_ID_IDENTITY uses Developer ID, CI without falls back
to ad-hoc for forks."
```

---

### Task 2: Create `Scripts/notarize.sh`

**Files:**
- Create: `Scripts/notarize.sh`

- [ ] **Step 1: Create the notarize script**

```zsh
#!/bin/zsh
set -euo pipefail

# Usage: notarize.sh <zip-path>
# Required env vars: NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER_ID
# The zip must contain a single .app at its root.

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <zip-path>"
  exit 1
fi

ZIP_PATH="$1"

for var in NOTARY_KEY NOTARY_KEY_ID NOTARY_ISSUER_ID; do
  if [[ -z "${(P)var:-}" ]]; then
    echo "Error: $var is not set"
    exit 1
  fi
done

WORK_DIR="$(mktemp -d)"
KEY_FILE="$WORK_DIR/notary-key.p8"
trap 'rm -rf "$WORK_DIR"' EXIT

# Write the API key to a temp file.
echo "$NOTARY_KEY" > "$KEY_FILE"

echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-api-key "$KEY_FILE" \
  --apple-api-key-id "$NOTARY_KEY_ID" \
  --apple-api-issuer "$NOTARY_ISSUER_ID" \
  --wait

# Extract the app for stapling.
STAPLE_DIR="$WORK_DIR/staple"
mkdir -p "$STAPLE_DIR"
ditto -x -k "$ZIP_PATH" "$STAPLE_DIR"

APP_PATH="$(find "$STAPLE_DIR" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Error: no .app found in zip"
  exit 1
fi

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

# Re-zip with the stapled app, replacing the original zip.
ARCHIVE_DIR="$WORK_DIR/archive"
mkdir -p "$ARCHIVE_DIR"
ditto "$APP_PATH" "$ARCHIVE_DIR/$(basename "$APP_PATH")"

# Preserve LICENSE if present in original zip.
LICENSE_PATH="$(find "$STAPLE_DIR" -maxdepth 1 -name 'LICENSE' -print -quit)"
if [[ -n "$LICENSE_PATH" ]]; then
  cp "$LICENSE_PATH" "$ARCHIVE_DIR/LICENSE"
fi

ditto -c -k --sequesterRsrc "$ARCHIVE_DIR" "$ZIP_PATH"

echo "Notarization complete."
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x Scripts/notarize.sh
```

- [ ] **Step 3: Verify script syntax**

```bash
zsh -n Scripts/notarize.sh
```
Expected: no output (syntax OK).

- [ ] **Step 4: Commit**

```bash
git add Scripts/notarize.sh
git commit -m "feat: add notarize.sh for Apple notarization, stapling, and re-zip"
```

---

### Task 3: Update `release.yml` with test + release jobs

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Rewrite `release.yml`**

Replace the entire file with:

```yaml
name: Release

"on":
  push:
    branches:
      - main

permissions:
  contents: write

concurrency:
  group: release-main
  cancel-in-progress: false

jobs:
  test:
    runs-on: macos-26

    steps:
      - name: Check out repository
        uses: actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955 # v4.3.0

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Log and validate Xcode version
        run: |
          xcodebuild -version
          python3 - <<'PY'
          import re
          import subprocess
          import sys

          required = (26, 1, 1)
          output = subprocess.check_output(["xcodebuild", "-version"], text=True).splitlines()[0]
          version_text = output.split()[1]
          match = re.match(r"(\d+)\.(\d+)(?:\.(\d+))?", version_text)
          if match is None:
              raise SystemExit(f"Could not parse Xcode version from: {version_text}")

          actual = tuple(int(part) for part in match.groups(default="0"))
          if actual < required:
              raise SystemExit(
                  f"Xcode {version_text} is older than required 26.1.1"
              )

          print(f"Using Xcode {version_text}")
          PY

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Run MarkdownRenderingTests
        run: xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=

      - name: Run MarkdownQuickLookPreviewExtensionTests
        run: xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=

      - name: Run MarkdownQuickLookAppTests
        run: xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=

  release:
    needs: test
    runs-on: macos-26

    steps:
      - name: Check out repository
        uses: actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955 # v4.3.0

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Set up signing keychain
        if: ${{ env.DEVELOPER_ID_CERT_BASE64 != '' }}
        env:
          DEVELOPER_ID_CERT_BASE64: ${{ secrets.DEVELOPER_ID_CERT_BASE64 }}
          DEVELOPER_ID_CERT_PASSWORD: ${{ secrets.DEVELOPER_ID_CERT_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          CERT_PATH="$RUNNER_TEMP/developer_id.p12"
          KEYCHAIN_PATH="$RUNNER_TEMP/signing.keychain-db"

          echo "$DEVELOPER_ID_CERT_BASE64" | base64 --decode > "$CERT_PATH"

          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          security import "$CERT_PATH" \
            -P "$DEVELOPER_ID_CERT_PASSWORD" \
            -A \
            -t cert \
            -f pkcs12 \
            -k "$KEYCHAIN_PATH"

          security set-key-partition-list \
            -S apple-tool:,apple: \
            -k "$KEYCHAIN_PASSWORD" \
            "$KEYCHAIN_PATH"

          security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

          IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
          echo "DEVELOPER_ID_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"

      - name: Build release artifact
        env:
          DEVELOPER_ID_IDENTITY: ${{ env.DEVELOPER_ID_IDENTITY }}
        run: ./Scripts/build-release.sh

      - name: Notarize
        if: ${{ env.DEVELOPER_ID_IDENTITY != '' }}
        env:
          NOTARY_KEY: ${{ secrets.NOTARY_KEY }}
          NOTARY_KEY_ID: ${{ secrets.NOTARY_KEY_ID }}
          NOTARY_ISSUER_ID: ${{ secrets.NOTARY_ISSUER_ID }}
        run: ./Scripts/notarize.sh dist/MarkdownQuickLook-macOS.zip

      - name: Derive rolling release metadata
        id: release_meta
        shell: bash
        run: |
          timestamp="$(date -u +'%Y%m%d-%H%M%S')"
          short_sha="${GITHUB_SHA::7}"
          tag="main-${timestamp}-${short_sha}"
          title="Rolling release ${tag}"
          run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

          {
            echo "tag=${tag}"
            echo "title=${title}"
            echo "run_url=${run_url}"
          } >> "$GITHUB_OUTPUT"

      - name: Create GitHub release
        env:
          GH_TOKEN: ${{ github.token }}
          RELEASE_TAG: ${{ steps.release_meta.outputs.tag }}
          RELEASE_TITLE: ${{ steps.release_meta.outputs.title }}
          RELEASE_RUN_URL: ${{ steps.release_meta.outputs.run_url }}
        shell: bash
        run: |
          cat > release-notes.txt <<EOF
          Automated rolling build from main.

          Commit: ${GITHUB_SHA}
          Run: ${RELEASE_RUN_URL}
          EOF

          gh release create "${RELEASE_TAG}" \
            dist/MarkdownQuickLook-macOS.zip \
            --repo "${GITHUB_REPOSITORY}" \
            --title "${RELEASE_TITLE}" \
            --notes-file release-notes.txt \
            --target "${GITHUB_SHA}"

      - name: Clean up keychain
        if: always()
        run: |
          KEYCHAIN_PATH="$RUNNER_TEMP/signing.keychain-db"
          if [[ -f "$KEYCHAIN_PATH" ]]; then
            security delete-keychain "$KEYCHAIN_PATH"
          fi
```

- [ ] **Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"
```
Expected: no output (valid YAML). If `yaml` module not available: `python3 -c "import json; print('ok')"` and visually inspect indentation.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: split CI into test + release jobs with notarization

The release job imports a Developer ID certificate from secrets,
signs the build with it, notarizes via notarytool, staples the
ticket, and publishes. Forks without secrets fall back to ad-hoc."
```

---

### Task 4: Add GitHub secrets and verify CI

**Files:** None (GitHub settings + verification)

- [ ] **Step 1: Export the Developer ID certificate as `.p12`**

In Keychain Access:
1. Find "Developer ID Application: Reza KAREGARAN (42QK7B5HYB)".
2. Expand it to show the private key.
3. Select both the certificate and key, right-click > Export 2 Items.
4. Save as `developer_id.p12` with a strong password.

- [ ] **Step 2: Base64-encode the `.p12`**

```bash
base64 -i developer_id.p12 | pbcopy
```

The base64 string is now on your clipboard.

- [ ] **Step 3: Add all six secrets to the GitHub repository**

Go to https://github.com/rkaregaran/MarkdownQuickLook/settings/secrets/actions and add:

| Name | Value |
|---|---|
| `DEVELOPER_ID_CERT_BASE64` | Paste the base64 from clipboard |
| `DEVELOPER_ID_CERT_PASSWORD` | The password from step 1 |
| `NOTARY_KEY` | Full contents of your `.p8` API key file |
| `NOTARY_KEY_ID` | Key ID from App Store Connect |
| `NOTARY_ISSUER_ID` | Issuer ID from App Store Connect |
| `KEYCHAIN_PASSWORD` | Any random string (e.g., `openssl rand -base64 24`) |

- [ ] **Step 4: Push and verify CI**

```bash
git push
```

Monitor the workflow at https://github.com/rkaregaran/MarkdownQuickLook/actions. Expected:
- `test` job passes (unchanged).
- `release` job: sets up keychain, builds with Developer ID, notarizes, staples, creates release.

- [ ] **Step 5: Verify the notarized release**

Download the zip from the GitHub release. Extract and check:

```bash
spctl -a -vvv -t install /path/to/MarkdownQuickLook.app
```

Expected: `accepted` with `source=Notarized Developer ID`.

---

### Task 5: Restore app group and settings sharing

**Files:**
- Modify: `MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements`
- Modify: `MarkdownQuickLookPreviewExtension/PreviewViewController.swift:159-163`
- Modify: `MarkdownQuickLookApp/App/StatusView.swift:1-50`

This task is only done AFTER Task 4 is verified — the notarized build must eliminate the App Data Protection dialog.

- [ ] **Step 1: Restore app group to extension entitlements**

Replace the contents of `MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.rzkr.MarkdownQuickLook</string>
	</array>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 2: Restore settings reading in PreviewViewController**

In `MarkdownQuickLookPreviewExtension/PreviewViewController.swift`, replace the `renderPayload` method:

```swift
    private static func renderPayload(
        for document: MarkdownPreparedDocument,
        shouldContinue: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> MarkdownRenderPayload {
        let settings = MarkdownSettingsStore().settings
        return try await MarkdownDocumentRenderer(settings: settings).render(document: document, shouldContinue: shouldContinue)
    }
```

- [ ] **Step 3: Remove DisclosureGroup deferral from StatusView**

In `MarkdownQuickLookApp/App/StatusView.swift`, replace the `DisclosureGroup` block and the `SettingsPanel` extraction with a direct settings section. Change `StatusView` to:

```swift
struct StatusView: View {
    private let experience = InstallExperience.current()
    @StateObject private var settingsStore = MarkdownSettingsStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: experience.state == .installed ? "checkmark.circle.fill" : "arrow.down.app.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(experience.state == .installed ? .green : .orange)

            Text(experience.headline)
                .font(.system(.title, design: .rounded).weight(.bold))

            Text(experience.bodyText)
                .font(.body)
                .foregroundStyle(.secondary)

            Text(experience.reassuranceText)
                .font(.body.weight(.medium))

            VStack(alignment: .leading, spacing: 8) {
                Text(experience.stepsTitle)
                .font(.headline)

                ForEach(experience.usageSteps, id: \.self) { step in
                    Text("• \(step)")
                        .font(.body)
                }
            }

            Text(experience.caveatText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            settingsSection

            Button(experience.primaryActionTitle) {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 560)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Aa")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(settingsStore.settings.textSizeLevel.rawValue) },
                            set: { settingsStore.settings.textSizeLevel = TextSizeLevel(rawValue: Int($0)) ?? .medium }
                        ),
                        in: 0...6,
                        step: 1
                    )
                    Text("Aa")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }

                Text(settingsStore.settings.textSizeLevel.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Font", selection: $settingsStore.settings.fontFamily) {
                ForEach(FontFamily.allCases, id: \.self) { family in
                    Text(family.displayName).tag(family)
                }
            }
            .pickerStyle(.segmented)

            previewSnippet
        }
    }

    private var fontDesign: Font.Design {
        switch settingsStore.settings.fontFamily {
        case .system: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }

    private var previewSnippet: some View {
        let scale = settingsStore.settings.textSizeLevel.scaleFactor

        return GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("Heading")
                    .font(.system(size: 20 * scale, weight: .semibold, design: fontDesign))
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.system(size: 15 * scale, design: fontDesign))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

Remove the separate `private struct SettingsPanel` that is no longer needed.

- [ ] **Step 4: Run tests**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements \
       MarkdownQuickLookPreviewExtension/PreviewViewController.swift \
       MarkdownQuickLookApp/App/StatusView.swift
git commit -m "feat: restore app group and settings sharing

Now that the release is notarized, the App Data Protection dialog
no longer appears. The extension reads shared settings from the
app group container, and the host app shows the settings panel
directly."
```

---

### Task 6: Update README with complete setup instructions

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Install section and Notarization section**

Replace the Install section's warning about unsigned apps:

```markdown
## Install

[Download latest release](https://github.com/rkaregaran/MarkdownQuickLook/releases/latest)

1. Download `MarkdownQuickLook-macOS.zip` from GitHub Releases.
2. Unzip it.
3. Drag `MarkdownQuickLook.app` into `/Applications`.
4. Open `MarkdownQuickLook.app` once, then click `Close App`. You should not need to open it again after that first successful launch.
```

- [ ] **Step 2: Add CI secrets setup to the Notarization section**

Append to the existing Notarization section in README.md:

```markdown
### Creating an App Store Connect API Key

1. Go to https://appstoreconnect.apple.com/access/integrations/api.
2. Click **Generate API Key** (or **+**).
3. Name: `MarkdownQuickLook CI`, Access: **Developer**.
4. Click Generate and **download the `.p8` file immediately** (one-time download).
5. Note the **Key ID** and the **Issuer ID** at the top of the page.

### CI Secrets for Notarized Releases

Add these secrets at https://github.com/rkaregaran/MarkdownQuickLook/settings/secrets/actions:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_BASE64` | `.p12` export of Developer ID Application certificate, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_CERT_PASSWORD` | Password used when exporting the `.p12` |
| `NOTARY_KEY` | Full contents of the `.p8` API key file |
| `NOTARY_KEY_ID` | Key ID from App Store Connect |
| `NOTARY_ISSUER_ID` | Issuer ID from App Store Connect |
| `KEYCHAIN_PASSWORD` | Any random string (e.g., `openssl rand -base64 24`) |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README with notarized install flow and CI secrets setup"
```
