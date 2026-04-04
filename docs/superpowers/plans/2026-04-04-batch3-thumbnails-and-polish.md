# Batch 3: Thumbnails & Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Finder thumbnail generation for `.md` files and labeled headers for special code blocks (mermaid, math).

**Architecture:** Thumbnails are a new Quick Look extension target (`QLThumbnailProvider`) that reuses the `MarkdownRendering` framework. Labeled code blocks are a small addition to the existing `appendCodeBlock` method.

**Tech Stack:** Swift, AppKit, QuickLookThumbnailing (`QLThumbnailProvider`), XCTest

---

### Task 1: Labeled Special Code Blocks

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add label logic to `appendCodeBlock`**

In `MarkdownDocumentRenderer.swift`, find the `appendCodeBlock` method (around line 719). Add a label line before the code content for recognized diagram/math languages. Replace the method:

```swift
    private func appendCodeBlock(_ code: String, language: String?, to output: NSMutableAttributedString) {
        let scale = settings.textSizeLevel.scaleFactor
        let padding = 10 * scale
        let font = NSFont.monospacedSystemFont(ofSize: 13 * scale, weight: .regular)

        let textBlock = RoundedTextBlock()
        textBlock.backgroundColor = NSColor(white: 0.5, alpha: 0.12)
        textBlock.setContentWidth(100, type: .percentageValueType)
        for edge: NSRectEdge in [.minX, .maxX, .minY, .maxY] {
            textBlock.setWidth(padding, type: .absoluteValueType, for: .padding, edge: edge)
        }

        let codeStyle = NSMutableParagraphStyle()
        codeStyle.textBlocks = [textBlock]
        codeStyle.lineSpacing = 2 * scale

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: codeStyle
        ]

        let content: String
        if let label = codeBlockLabel(for: language) {
            content = label + "\n" + code
        } else {
            content = code
        }

        let highlighted = NSMutableAttributedString(string: content, attributes: baseAttributes)

        // Style the label line if present.
        if let label = codeBlockLabel(for: language) {
            let labelRange = NSRange(location: 0, length: label.count)
            highlighted.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11 * scale, weight: .semibold), range: labelRange)
            highlighted.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: labelRange)
            // Apply syntax highlighting only to the code portion, not the label.
            let codeRange = NSRange(location: label.count + 1, length: code.count)
            let codeString = NSMutableAttributedString(attributedString: highlighted.attributedSubstring(from: codeRange))
            applySyntaxHighlighting(to: codeString, language: language, font: font)
            highlighted.replaceCharacters(in: codeRange, with: codeString)
        } else {
            applySyntaxHighlighting(to: highlighted, language: language, font: font)
        }

        output.append(highlighted)
    }

    private func codeBlockLabel(for language: String?) -> String? {
        switch language {
        case "mermaid": return "📊 Mermaid Diagram"
        case "math", "latex", "tex": return "📐 Math Expression"
        case "diagram": return "📊 Diagram"
        default: return nil
        }
    }
```

- [ ] **Step 2: Write tests**

Add to `MarkdownDocumentRendererTests.swift`:

```swift
    func testRenderMermaidCodeBlockHasLabel() throws {
        let payload = try renderDocument(
            """
            ```mermaid
            graph TD
              A --> B
            ```
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertTrue(text.contains("Mermaid Diagram"))
        XCTAssertTrue(text.contains("graph TD"))
    }

    func testRenderMathCodeBlockHasLabel() throws {
        let payload = try renderDocument(
            """
            ```latex
            E = mc^2
            ```
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertTrue(text.contains("Math Expression"))
        XCTAssertTrue(text.contains("E = mc^2"))
    }

    func testRenderRegularCodeBlockHasNoLabel() throws {
        let payload = try renderDocument(
            """
            ```swift
            let x = 1
            ```
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertFalse(text.contains("Diagram"))
        XCTAssertFalse(text.contains("Expression"))
        XCTAssertTrue(text.contains("let x = 1"))
    }
```

- [ ] **Step 3: Run tests**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```

- [ ] **Step 4: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: add labeled headers for mermaid, math, and diagram code blocks"
```

---

### Task 2: Thumbnail Extension — Project Setup

**Files:**
- Modify: `project.yml`
- Create: `MarkdownQuickLookThumbnailExtension/Info.plist`
- Create: `MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements`

- [ ] **Step 1: Create the Info.plist**

Create `MarkdownQuickLookThumbnailExtension/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Markdown Quick Look Thumbnail</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionAttributes</key>
		<dict>
			<key>QLSupportedContentTypes</key>
			<array>
				<string>net.daringfireball.markdown</string>
			</array>
			<key>QLThumbnailMinimumDimension</key>
			<integer>75</integer>
		</dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.quicklook.thumbnail</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).ThumbnailProvider</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 2: Create the entitlements**

Create `MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 3: Add the target to project.yml**

Add after the `MarkdownQuickLookPreviewExtension` target (around line 59):

```yaml
  MarkdownQuickLookThumbnailExtension:
    type: app-extension
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: MarkdownQuickLookThumbnailExtension
        excludes:
          - Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.rzkr.MarkdownQuickLook.app.thumbnail
        INFOPLIST_FILE: MarkdownQuickLookThumbnailExtension/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_STYLE: Automatic
        ENABLE_APP_SANDBOX: YES
        ENABLE_USER_SELECTED_FILES: readonly
        CODE_SIGN_ENTITLEMENTS: MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements
    dependencies:
      - target: MarkdownRendering
```

- [ ] **Step 4: Add the thumbnail extension as a dependency of the host app**

In the `MarkdownQuickLookApp` target's `dependencies` section, add:

```yaml
      - target: MarkdownQuickLookThumbnailExtension
        embed: true
```

- [ ] **Step 5: Verify project generates**

```bash
xcodegen generate
```

Expected: `Created project at .../MarkdownQuickLook.xcodeproj`

- [ ] **Step 6: Commit**

```bash
git add project.yml MarkdownQuickLookThumbnailExtension/Info.plist MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements
git commit -m "feat: add thumbnail extension target to project"
```

---

### Task 3: Thumbnail Extension — Implementation

**Files:**
- Create: `MarkdownQuickLookThumbnailExtension/ThumbnailProvider.swift`

- [ ] **Step 1: Create ThumbnailProvider.swift**

Create `MarkdownQuickLookThumbnailExtension/ThumbnailProvider.swift`:

```swift
import AppKit
import MarkdownRendering
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let maximumSize = request.maximumSize
        let scale = request.scale

        handler(QLThumbnailReply(contextSize: maximumSize, drawing: { context -> Bool in
            let renderer = MarkdownDocumentRenderer()

            guard let document = try? renderer.prepareDocument(fileAt: request.fileURL) else {
                return false
            }

            let payload = DispatchQueue.main.sync {
                renderer.render(document: document)
            }

            let attributed = payload.attributedContent

            // Set up drawing area with padding.
            let padding: CGFloat = 8
            let drawRect = CGRect(
                x: padding,
                y: padding,
                width: maximumSize.width - padding * 2,
                height: maximumSize.height - padding * 2
            )

            // Draw white/dark background.
            let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = nsContext

            NSColor.textBackgroundColor.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: maximumSize)).fill()

            // Draw the attributed string, clipped to the thumbnail area.
            let framesetter = attributed
            framesetter.draw(in: drawRect)

            NSGraphicsContext.current = nil
            return true
        }), nil)
    }
}

private extension NSAttributedString {
    func draw(in rect: CGRect) {
        let textStorage = NSTextStorage(attributedString: self)
        let textContainer = NSTextContainer(containerSize: rect.size)
        let layoutManager = NSLayoutManager()

        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: rect.origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: rect.origin)
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
xcodegen generate
xcodebuild -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookApp -configuration Debug -destination 'platform=macOS' build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MarkdownQuickLookThumbnailExtension/ThumbnailProvider.swift
git commit -m "feat: implement thumbnail provider for markdown files"
```

---

### Task 4: Build, Install, and Verify

**Files:**
- Modify: `Scripts/build-release.sh` (if re-signing needed for thumbnail extension)

- [ ] **Step 1: Check if build-release.sh needs updating for the new extension**

The build-release.sh re-signs extensions when `DEVELOPER_ID_IDENTITY` is set. Check if the thumbnail extension also needs re-signing. Read the script and add the thumbnail extension to the re-signing block:

In `Scripts/build-release.sh`, find the re-signing section (the `if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]` block) and add the thumbnail extension before the host app signing:

```bash
  # Sign the thumbnail extension.
  THUMBNAIL_PATH="$DIST_APP_PATH/Contents/PlugIns/MarkdownQuickLookThumbnailExtension.appex"
  if [[ -d "$THUMBNAIL_PATH" ]]; then
    codesign --force --sign "$DEVELOPER_ID_IDENTITY" \
      --entitlements "$ROOT/MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements" \
      --options runtime \
      "$THUMBNAIL_PATH"
  fi
```

This must be added BEFORE the host app codesign (inside-out signing order).

- [ ] **Step 2: Build release**

```bash
./Scripts/build-release.sh
```

- [ ] **Step 3: Install and test**

```bash
rm -rf /Applications/MarkdownQuickLook.app
ditto dist/MarkdownQuickLook.app /Applications/MarkdownQuickLook.app
open /Applications/MarkdownQuickLook.app
sleep 3
pluginkit -e use -i com.rzkr.MarkdownQuickLook.app.preview
pluginkit -e use -i com.rzkr.MarkdownQuickLook.app.thumbnail
qlmanage -r
qlmanage -r cache
```

- [ ] **Step 4: Generate a thumbnail to verify**

```bash
qlmanage -t Fixtures/Sample.md -s 256 -o /tmp/
open /tmp/Sample.md.png
```

Expected: a 256px thumbnail image showing the rendered markdown content.

- [ ] **Step 5: Run all tests**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

- [ ] **Step 6: Commit**

```bash
git add Scripts/build-release.sh
git commit -m "feat: add thumbnail extension to release build re-signing"
```
