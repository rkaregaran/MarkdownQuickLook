# Markdown Quick Look Release Distribution Plan

## Objective

Ship a public MIT-licensed release flow for `MarkdownQuickLook` with:

- a release-facing host app window that reads as “installed successfully”
- a prominent `Close App` button that makes one-time launch behavior obvious
- a Release build script that outputs a GitHub-uploadable zip containing `MarkdownQuickLook.app`
- end-user docs for drag-to-`/Applications`, unsigned first launch, and “launch once, then quit”

## File Map

- `/Users/reza.karegaran/Code/quicklook-md/project.yml`
  Purpose: rename the built app product to `MarkdownQuickLook.app` and add an app test target
- `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/MarkdownQuickLookApp.swift`
  Purpose: remove the old `AppState` wiring so the window is static
- `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/StatusView.swift`
  Purpose: replace the developer-status screen with the install-confirmation UI
- `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/InstallExperience.swift`
  Purpose: centralize release-facing copy and usage steps in a small testable model
- `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/Tests/InstallExperienceTests.swift`
  Purpose: verify the one-time-launch copy and primary action title
- `/Users/reza.karegaran/Code/quicklook-md/Scripts/build-release.sh`
  Purpose: build a Release app, stage it into `dist/`, validate runtime packaging, and zip it
- `/Users/reza.karegaran/Code/quicklook-md/Scripts/dev-preview.sh`
  Purpose: keep local debug verification working after the product rename
- `/Users/reza.karegaran/Code/quicklook-md/.gitignore`
  Purpose: ignore `dist/`
- `/Users/reza.karegaran/Code/quicklook-md/README.md`
  Purpose: public install and maintainer release instructions
- `/Users/reza.karegaran/Code/quicklook-md/LICENSE`
  Purpose: MIT license text
- `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/AppDelegate.swift`
  Purpose: delete after the status window no longer tracks opened files
- `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/AppState.swift`
  Purpose: delete after the status window no longer tracks opened files

## Task 1: Rename the Built Product and Add a Host-App Test Target

### Step 1.1: Update `project.yml` for the release app name

Set the application product name so Release and Debug builds both output `MarkdownQuickLook.app`.

Add this setting under `MarkdownQuickLookApp.settings.base`:

```yaml
PRODUCT_NAME: MarkdownQuickLook
```

Expected result:

- the built bundle path becomes `.../MarkdownQuickLook.app`
- `CFBundleName` resolves to `MarkdownQuickLook`

### Step 1.2: Add a dedicated app test target

Add a new target that follows the repo’s existing pattern of compiling app source files directly into the test bundle:

```yaml
MarkdownQuickLookAppTests:
  type: bundle.unit-test
  platform: macOS
  deploymentTarget: "14.0"
  sources:
    - path: MarkdownQuickLookApp/App/InstallExperience.swift
    - path: MarkdownQuickLookApp/Tests
  settings:
    base:
      PRODUCT_BUNDLE_IDENTIFIER: com.example.MarkdownQuickLook.appTests
      GENERATE_INFOPLIST_FILE: YES
      TEST_HOST: ""
      BUNDLE_LOADER: ""
```

### Step 1.3: Write the failing app test first

Create `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/Tests/InstallExperienceTests.swift`:

```swift
import XCTest

final class InstallExperienceTests: XCTestCase {
    func testPrimaryActionTitleUsesCloseApp() {
        XCTAssertEqual(InstallExperience.primaryActionTitle, "Close App")
    }

    func testBodyCopyExplainsOneTimeLaunchBehavior() {
        XCTAssertTrue(InstallExperience.bodyText.contains("launched once"))
        XCTAssertTrue(InstallExperience.bodyText.contains("/Applications"))
    }

    func testUsageStepsMatchFinderQuickLookFlow() {
        XCTAssertEqual(
            InstallExperience.usageSteps,
            [
                "Select a Markdown file in Finder.",
                "Press Space to preview it with Quick Look."
            ]
        )
    }
}
```

### Step 1.4: Verify the test fails for the right reason

Run:

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

Expected failure:

- `InstallExperience` does not exist yet

### Step 1.5: Commit checkpoint

```bash
git add project.yml MarkdownQuickLookApp/Tests/InstallExperienceTests.swift
git commit -m "test: add install experience coverage"
```

## Task 2: Implement the Release Install Window

### Step 2.1: Add the copy model

Create `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/InstallExperience.swift`:

```swift
import Foundation

enum InstallExperience {
    static let headline = "Markdown preview is installed."
    static let bodyText = "MarkdownQuickLook has registered its Quick Look extension. After moving the app to /Applications, it only needs to be launched once."
    static let reassuranceText = "You can close this app now. You do not need to keep it open for Finder previews."
    static let caveatText = "Standard .md preview remains best-effort. Some macOS versions may still prefer Apple's built-in plain-text preview."
    static let primaryActionTitle = "Close App"
    static let usageSteps = [
        "Select a Markdown file in Finder.",
        "Press Space to preview it with Quick Look."
    ]
}
```

### Step 2.2: Replace the current `StatusView`

Rewrite `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/StatusView.swift` to render a static confirmation view. Use a large success icon, strong headline, two short paragraphs, a “How to use it” block, and a large primary button:

```swift
import AppKit
import SwiftUI

struct StatusView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            Text(InstallExperience.headline)
                .font(.largeTitle.weight(.bold))

            Text(InstallExperience.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            Text(InstallExperience.reassuranceText)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("How to use it")
                    .font(.headline)

                ForEach(Array(InstallExperience.usageSteps.enumerated()), id: \.offset) { index, step in
                    Text("\\(index + 1). \\(step)")
                }
            }

            Text(InstallExperience.caveatText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(InstallExperience.primaryActionTitle) {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 560)
    }
}
```

### Step 2.3: Remove dead app-state wiring

Update `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/MarkdownQuickLookApp.swift`:

```swift
import SwiftUI

@main
struct MarkdownQuickLookApp: App {
    var body: some Scene {
        WindowGroup {
            StatusView()
        }
        .windowResizability(.contentSize)
    }
}
```

Delete the now-unused files:

- `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/AppDelegate.swift`
- `/Users/reza.karegaran/Code/quicklook-md/MarkdownQuickLookApp/App/AppState.swift`

### Step 2.4: Verify green

Run:

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

Expected result:

- `MarkdownQuickLookAppTests` passes

### Step 2.5: Manual UX verification

Run:

```bash
./Scripts/dev-preview.sh
open .derivedData/Build/Products/Debug/MarkdownQuickLook.app
```

Check manually:

- the headline reads as installed/successful
- the `Close App` button is visually dominant
- the wording clearly says the app can be closed and does not need to stay open

### Step 2.6: Commit checkpoint

```bash
git add project.yml MarkdownQuickLookApp/App MarkdownQuickLookApp/Tests
git commit -m "feat: add release install experience"
```

## Task 3: Add the Release Packaging Flow

### Step 3.1: Write the failing packaging check first

Create a simple expectation by running a command that should fail before the script exists:

```bash
test -x Scripts/build-release.sh
```

Expected failure:

- `Scripts/build-release.sh` is missing

### Step 3.2: Ignore release artifacts

Update `/Users/reza.karegaran/Code/quicklook-md/.gitignore`:

```gitignore
dist/
```

### Step 3.3: Add the release build script

Create `/Users/reza.karegaran/Code/quicklook-md/Scripts/build-release.sh`:

```zsh
#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH="$ROOT/.derivedData/release-build"
DIST_DIR="$ROOT/dist"
APP_NAME="MarkdownQuickLook.app"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME"
DIST_APP_PATH="$DIST_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/MarkdownQuickLook-macOS.zip"

xcodegen generate
rm -rf "$DIST_DIR" "$DERIVED_DATA_PATH"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLookApp \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

ditto "$APP_PATH" "$DIST_APP_PATH"
"$ROOT/Scripts/check-preview-runtime.sh" "$DIST_APP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$DIST_APP_PATH" "$ZIP_PATH"

echo
echo "Release app:"
echo "  $DIST_APP_PATH"
echo
echo "Release zip:"
echo "  $ZIP_PATH"
echo
shasum -a 256 "$ZIP_PATH"
```

### Step 3.4: Keep debug verification aligned with the new app name

Update `Scripts/dev-preview.sh` to:

```zsh
APP_PATH="$ROOT/.derivedData/Build/Products/Debug/MarkdownQuickLook.app"
```

### Step 3.5: Verify green

Run:

```bash
chmod +x Scripts/build-release.sh
./Scripts/build-release.sh
```

Then confirm the zip expands correctly:

```bash
rm -rf /tmp/markdown-quicklook-release-check
mkdir -p /tmp/markdown-quicklook-release-check
ditto -x -k dist/MarkdownQuickLook-macOS.zip /tmp/markdown-quicklook-release-check
test -d /tmp/markdown-quicklook-release-check/MarkdownQuickLook.app
```

Expected result:

- the Release app exists in `dist/`
- the zip exists in `dist/`
- unzip yields `MarkdownQuickLook.app` at the top level

### Step 3.6: Commit checkpoint

```bash
git add .gitignore Scripts/build-release.sh Scripts/dev-preview.sh
git commit -m "build: add release packaging script"
```

## Task 4: Add MIT Licensing and Rewrite the README for Public Use

### Step 4.1: Add the MIT license

Create `/Users/reza.karegaran/Code/quicklook-md/LICENSE` with standard MIT text using the current copyright holder:

```text
MIT License

Copyright (c) 2026 Reza Karegaran

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Step 4.2: Rewrite the README

Replace `/Users/reza.karegaran/Code/quicklook-md/README.md` with:

````md
# Markdown Quick Look

Best-effort Markdown preview for Finder Quick Look on macOS.

## Install

1. Download `MarkdownQuickLook-macOS.zip` from GitHub Releases.
2. Unzip it.
3. Drag `MarkdownQuickLook.app` into `/Applications`.
4. `Control-click` the app and choose `Open` the first time.
5. Launch it once, then click `Close App`.

## Use It

1. In Finder, select a `.md` file.
2. Press `Space`.

## Important Caveat

`MarkdownQuickLook` targets the standard Markdown content type `net.daringfireball.markdown`, but Finder may still prefer Apple's built-in plain-text preview on some macOS versions.

## Build From Source

```bash
xcodegen generate
open MarkdownQuickLook.xcodeproj
```

## Local Verification

```bash
./Scripts/dev-preview.sh
```

## Build a Release Zip

```bash
./Scripts/build-release.sh
```
````

Keep the end-user install section above all developer-oriented instructions.

### Step 4.3: Verify docs shape

Run:

```bash
sed -n '1,220p' README.md
test -f LICENSE
```

Check manually:

- install steps are the first actionable section
- the unsigned first-launch flow is explicit
- “launch once, then close it” is explicit

### Step 4.4: Commit checkpoint

```bash
git add README.md LICENSE
git commit -m "docs: prepare public distribution docs"
```

## Task 5: Final Verification Before Merge or Release

### Step 5.1: Regenerate the project

```bash
xcodegen generate
```

### Step 5.2: Run all automated tests

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

### Step 5.3: Run both build flows

```bash
./Scripts/dev-preview.sh
./Scripts/build-release.sh
```

### Step 5.4: Manual product checks

Verify manually:

- `dist/MarkdownQuickLook.app` opens and shows the install-confirmation UI
- the primary button says `Close App`
- the release zip expands to `MarkdownQuickLook.app`
- Quick Look still works after launching the installed app once

### Step 5.5: Final commit

```bash
git status --short
git add .
git commit -m "feat: prepare app for public release"
```
