# Markdown Quick Look App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS host app with an embedded Quick Look Preview Extension that best-effort targets `net.daringfireball.markdown` and renders `.md` files as formatted Markdown in Finder Quick Look.

**Architecture:** Use XcodeGen as the source of truth for the macOS app, preview extension, and shared rendering framework. Keep Markdown parsing and formatting in a small shared framework, keep Quick Look wiring isolated inside the extension target, and keep the host app limited to status text and local verification guidance.

**Tech Stack:** Swift, SwiftUI, AppKit, Quartz Quick Look APIs, Foundation Markdown parsing, XcodeGen 2.45.3, Xcode 26.1.1

---

## File Structure

- `/.gitignore`: Ignore generated Xcode, build, and workspace state
- `/project.yml`: XcodeGen project definition for the app, extension, framework, and tests
- `/MarkdownQuickLookApp/Info.plist`: Host app metadata and Markdown document type claim
- `/MarkdownQuickLookApp/App/MarkdownQuickLookApp.swift`: App entry point
- `/MarkdownQuickLookApp/App/StatusView.swift`: Minimal status and caveat UI
- `/MarkdownQuickLookPreviewExtension/Info.plist`: Quick Look Preview Extension metadata
- `/MarkdownQuickLookPreviewExtension/PreviewViewController.swift`: Quick Look entry point and renderer wiring
- `/MarkdownQuickLookPreviewExtension/PreviewRootView.swift`: SwiftUI preview container
- `/MarkdownQuickLookPreviewExtension/MarkdownTextView.swift`: AppKit bridge for displaying `NSAttributedString`
- `/MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`: File loading, block formatting, and inline Markdown rendering
- `/MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`: Shared renderer behavior tests
- `/Fixtures/Sample.md`: Manual Quick Look verification file
- `/Scripts/dev-preview.sh`: Build, reload, and local verification helper
- `/README.md`: Setup and verification instructions

### Task 1: Bootstrap The Repo And Generate A Buildable Xcode Project

**Files:**
- Create: `/.gitignore`
- Create: `/project.yml`
- Create: `/MarkdownQuickLookApp/Info.plist`
- Create: `/MarkdownQuickLookApp/App/MarkdownQuickLookApp.swift`
- Create: `/MarkdownQuickLookApp/App/StatusView.swift`
- Create: `/MarkdownQuickLookPreviewExtension/Info.plist`
- Create: `/MarkdownQuickLookPreviewExtension/PreviewViewController.swift`
- Create: `/MarkdownQuickLookPreviewExtension/PreviewRootView.swift`
- Create: `/MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`

- [ ] **Step 1: Initialize git and ignore generated artifacts**

Run:

```bash
git init -b main
mkdir -p MarkdownQuickLookApp/App MarkdownQuickLookPreviewExtension MarkdownRendering/Sources MarkdownRendering/Tests Fixtures Scripts
```

Create `/.gitignore`:

```gitignore
.DS_Store
.derivedData/
.build/
.superpowers/
MarkdownQuickLook.xcodeproj/
*.xcworkspace/
*.xcuserstate
*.xcuserdata/
```

- [ ] **Step 2: Create the XcodeGen project spec and baseline source files**

Create `/project.yml`:

```yaml
name: MarkdownQuickLook
options:
  minimumXcodeGenVersion: 2.45.3
settings:
  base:
    SWIFT_VERSION: 5.0
targets:
  MarkdownQuickLookApp:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: MarkdownQuickLookApp/App
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MarkdownQuickLook.app
        INFOPLIST_FILE: MarkdownQuickLookApp/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_STYLE: Automatic
    dependencies:
      - target: MarkdownQuickLookPreviewExtension
        embed: true

  MarkdownQuickLookPreviewExtension:
    type: app-extension
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: MarkdownQuickLookPreviewExtension
        excludes:
          - Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MarkdownQuickLook.app.preview
        INFOPLIST_FILE: MarkdownQuickLookPreviewExtension/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_STYLE: Automatic
        ENABLE_APP_SANDBOX: YES
        ENABLE_USER_SELECTED_FILES: readonly
    dependencies:
      - target: MarkdownRendering

  MarkdownRendering:
    type: framework
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: MarkdownRendering/Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MarkdownQuickLook.rendering
        GENERATE_INFOPLIST_FILE: YES

  MarkdownRenderingTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: MarkdownRendering/Tests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MarkdownQuickLook.renderingTests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: ""
        BUNDLE_LOADER: ""
    dependencies:
      - target: MarkdownRendering
```

Create `/MarkdownQuickLookApp/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Markdown Document</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>net.daringfireball.markdown</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

Create `/MarkdownQuickLookPreviewExtension/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
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
			<key>QLIsDataBasedPreview</key>
			<false/>
			<key>QLSupportedContentTypes</key>
			<array>
				<string>net.daringfireball.markdown</string>
			</array>
			<key>QLSupportsSearchableItems</key>
			<false/>
		</dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.quicklook.preview</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).PreviewViewController</string>
	</dict>
</dict>
</plist>
```

Create `/MarkdownQuickLookApp/App/MarkdownQuickLookApp.swift`:

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

Create `/MarkdownQuickLookApp/App/StatusView.swift`:

```swift
import SwiftUI

struct StatusView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Markdown Quick Look")
                .font(.largeTitle.weight(.semibold))

            Text("This app installs a Quick Look Preview Extension that best-effort targets standard .md files.")

            Text("Finder may still keep the built-in plain-text preview on some macOS releases.")
                .foregroundStyle(.secondary)

            Text("Project source of truth: project.yml")
                .font(.system(.body, design: .monospaced))
        }
        .padding(24)
        .frame(width: 560)
    }
}
```

Create `/MarkdownQuickLookPreviewExtension/PreviewViewController.swift`:

```swift
import Cocoa
import Quartz
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let hostingView = NSHostingView(
        rootView: PreviewRootView(title: "Markdown Preview", message: "Loading preview...", attributedContent: nil)
    )

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func preparePreviewOfFile(at url: URL) async throws {
        hostingView.rootView = PreviewRootView(
            title: url.lastPathComponent,
            message: "Renderer wiring lands in Task 3.",
            attributedContent: nil
        )
    }
}
```

Create `/MarkdownQuickLookPreviewExtension/PreviewRootView.swift`:

```swift
import AppKit
import SwiftUI

struct PreviewRootView: View {
    let title: String
    let message: String?
    let attributedContent: NSAttributedString?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            if let attributedContent {
                Text(attributedContent.string)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(message ?? "No preview available.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
```

Create `/MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`:

```swift
import Foundation

public struct MarkdownRenderPayload {
    public let title: String
    public let attributedContent: NSAttributedString

    public init(title: String, attributedContent: NSAttributedString) {
        self.title = title
        self.attributedContent = attributedContent
    }
}

public enum MarkdownDocumentRendererError: Error, Equatable {
    case unreadableFile(URL)
    case emptyDocument(URL)
}

public final class MarkdownDocumentRenderer {
    public init() {}

    public func render(fileAt url: URL) throws -> MarkdownRenderPayload {
        MarkdownRenderPayload(
            title: url.lastPathComponent,
            attributedContent: NSAttributedString(string: "Renderer not implemented yet.")
        )
    }
}
```

- [ ] **Step 3: Generate the Xcode project and verify the baseline app builds**

Run:

```bash
xcodegen generate
xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLookApp \
  -destination 'platform=macOS' \
  build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit the scaffold**

Run:

```bash
git add .gitignore project.yml MarkdownQuickLookApp MarkdownQuickLookPreviewExtension MarkdownRendering
git commit -m "chore: scaffold markdown quick look app"
```

### Task 2: Implement The Shared Markdown Renderer With Tests First

**Files:**
- Modify: `/MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Test: `/MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Write the failing renderer tests**

Create `/MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`:

```swift
import XCTest
@testable import MarkdownRendering

final class MarkdownDocumentRendererTests: XCTestCase {
    func testRenderFormatsHeadingsListsAndQuotes() throws {
        let url = try temporaryMarkdownFile(
            """
            # Title

            Paragraph with `code`.

            - First item
            > Quoted line
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try MarkdownDocumentRenderer().render(fileAt: url)

        XCTAssertEqual(payload.title, url.lastPathComponent)
        XCTAssertTrue(payload.attributedContent.string.contains("Title"))
        XCTAssertTrue(payload.attributedContent.string.contains("Paragraph with code."))
        XCTAssertTrue(payload.attributedContent.string.contains("• First item"))
        XCTAssertTrue(payload.attributedContent.string.contains("│ Quoted line"))
    }

    func testRenderPreservesLinkAttribute() throws {
        let url = try temporaryMarkdownFile("[OpenAI](https://openai.com)")
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try MarkdownDocumentRenderer().render(fileAt: url)
        let nsString = payload.attributedContent.string as NSString
        let range = nsString.range(of: "OpenAI")

        let link = payload.attributedContent.attribute(.link, at: range.location, effectiveRange: nil) as? URL

        XCTAssertEqual(link, URL(string: "https://openai.com"))
    }

    func testRenderThrowsEmptyDocumentForWhitespaceOnlyInput() throws {
        let url = try temporaryMarkdownFile("   \n\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MarkdownDocumentRenderer().render(fileAt: url)) { error in
            XCTAssertEqual(error as? MarkdownDocumentRendererError, .emptyDocument(url))
        }
    }

    func testRenderThrowsUnreadableFileWhenFileIsMissing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        XCTAssertThrowsError(try MarkdownDocumentRenderer().render(fileAt: url)) { error in
            XCTAssertEqual(error as? MarkdownDocumentRendererError, .unreadableFile(url))
        }
    }

    private func temporaryMarkdownFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
```

- [ ] **Step 2: Run the renderer tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownRenderingTests \
  -destination 'platform=macOS'
```

Expected: FAIL because the placeholder renderer returns `"Renderer not implemented yet."` and does not throw the expected errors.

- [ ] **Step 3: Write the minimal renderer implementation**

Replace `/MarkdownRendering/Sources/MarkdownDocumentRenderer.swift` with:

```swift
import AppKit
import Foundation

public struct MarkdownRenderPayload {
    public let title: String
    public let attributedContent: NSAttributedString

    public init(title: String, attributedContent: NSAttributedString) {
        self.title = title
        self.attributedContent = attributedContent
    }
}

public enum MarkdownDocumentRendererError: Error, Equatable, LocalizedError {
    case unreadableFile(URL)
    case emptyDocument(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let url):
            return "Quick Look could not read \(url.lastPathComponent)."
        case .emptyDocument(let url):
            return "\(url.lastPathComponent) is empty."
        }
    }
}

public final class MarkdownDocumentRenderer {
    public init() {}

    public func render(fileAt url: URL) throws -> MarkdownRenderPayload {
        let source: String

        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MarkdownDocumentRendererError.unreadableFile(url)
        }

        guard source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MarkdownDocumentRendererError.emptyDocument(url)
        }

        let formatted = NSMutableAttributedString()
        let baseURL = url.deletingLastPathComponent()
        var isInsideCodeFence = false
        var fencedCodeLines: [String] = []

        for line in source.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if isInsideCodeFence {
                    appendCodeBlock(fencedCodeLines.joined(separator: "\n"), to: formatted)
                    fencedCodeLines.removeAll()
                    isInsideCodeFence = false
                } else {
                    isInsideCodeFence = true
                }
                continue
            }

            if isInsideCodeFence {
                fencedCodeLines.append(line)
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                ensureBlankLine(in: formatted)
                continue
            }

            if let heading = heading(from: line) {
                appendStyledText(heading.text, attributes: headingAttributes(level: heading.level), to: formatted)
                ensureBlankLine(in: formatted)
                continue
            }

            if let listItem = listItem(from: line) {
                appendInlineMarkdown("• \(listItem)", baseURL: baseURL, baseAttributes: bodyAttributes(), to: formatted)
                appendNewline(to: formatted)
                continue
            }

            if let quote = blockQuote(from: line) {
                appendInlineMarkdown("│ \(quote)", baseURL: baseURL, baseAttributes: quoteAttributes(), to: formatted)
                ensureBlankLine(in: formatted)
                continue
            }

            appendInlineMarkdown(line, baseURL: baseURL, baseAttributes: bodyAttributes(), to: formatted)
            ensureBlankLine(in: formatted)
        }

        if isInsideCodeFence, fencedCodeLines.isEmpty == false {
            appendCodeBlock(fencedCodeLines.joined(separator: "\n"), to: formatted)
        }

        return MarkdownRenderPayload(
            title: url.lastPathComponent,
            attributedContent: formatted
        )
    }

    private func heading(from line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }

        guard hashes.isEmpty == false, hashes.count <= 6 else {
            return nil
        }

        let text = trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard text.isEmpty == false else {
            return nil
        }

        return (hashes.count, text)
    }

    private func listItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("- ") {
            return String(trimmed.dropFirst(2))
        }

        if trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2))
        }

        return nil
    }

    private func blockQuote(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("> ") else {
            return nil
        }

        return String(trimmed.dropFirst(2))
    }

    private func appendInlineMarkdown(
        _ text: String,
        baseURL: URL,
        baseAttributes: [NSAttributedString.Key: Any],
        to output: NSMutableAttributedString
    ) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: text, options: options, baseURL: baseURL)) ?? AttributedString(text)
        let attributed = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))
        output.append(attributed)
    }

    private func appendStyledText(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        to output: NSMutableAttributedString
    ) {
        output.append(NSAttributedString(string: text, attributes: attributes))
    }

    private func appendCodeBlock(_ code: String, to output: NSMutableAttributedString) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 10

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.textBackgroundColor,
            .paragraphStyle: paragraph
        ]

        output.append(NSAttributedString(string: code, attributes: attributes))
        ensureBlankLine(in: output)
    }

    private func ensureBlankLine(in output: NSMutableAttributedString) {
        let suffix = output.string

        if suffix.hasSuffix("\n\n") {
            return
        }

        if suffix.hasSuffix("\n") {
            output.append(NSAttributedString(string: "\n"))
        } else {
            output.append(NSAttributedString(string: "\n\n"))
        }
    }

    private func appendNewline(to output: NSMutableAttributedString) {
        output.append(NSAttributedString(string: "\n"))
    }

    private func bodyAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 10

        return [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private func quoteAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 10

        return [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
    }

    private func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let size: CGFloat

        switch level {
        case 1:
            size = 30
        case 2:
            size = 24
        case 3:
            size = 20
        default:
            size = 17
        }

        return [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
    }
}
```

- [ ] **Step 4: Run the renderer tests to verify they pass**

Run:

```bash
xcodebuild test \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownRenderingTests \
  -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit the renderer**

Run:

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: add markdown renderer"
```

### Task 3: Wire The Preview Extension To The Shared Renderer

**Files:**
- Create: `/MarkdownQuickLookPreviewExtension/MarkdownTextView.swift`
- Modify: `/MarkdownQuickLookPreviewExtension/PreviewRootView.swift`
- Modify: `/MarkdownQuickLookPreviewExtension/PreviewViewController.swift`
- Modify: `/MarkdownQuickLookApp/App/StatusView.swift`

- [ ] **Step 1: Add the native AppKit text view bridge**

Create `/MarkdownQuickLookPreviewExtension/MarkdownTextView.swift`:

```swift
import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributedText)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.textStorage?.setAttributedString(attributedText)
    }
}
```

- [ ] **Step 2: Replace the placeholder preview UI with the real rich-text container**

Replace `/MarkdownQuickLookPreviewExtension/PreviewRootView.swift` with:

```swift
import AppKit
import SwiftUI

struct PreviewRootView: View {
    let title: String
    let message: String?
    let attributedContent: NSAttributedString?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            if let attributedContent {
                MarkdownTextView(attributedText: attributedContent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(message ?? "No preview available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
```

- [ ] **Step 3: Connect the Quick Look entry point to the shared renderer**

Replace `/MarkdownQuickLookPreviewExtension/PreviewViewController.swift` with:

```swift
import Cocoa
import MarkdownRendering
import Quartz
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let renderer = MarkdownDocumentRenderer()
    private let hostingView = NSHostingView(
        rootView: PreviewRootView(title: "Markdown Preview", message: "Loading preview...", attributedContent: nil)
    )

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func preparePreviewOfFile(at url: URL) async throws {
        do {
            let payload = try renderer.render(fileAt: url)
            hostingView.rootView = PreviewRootView(
                title: payload.title,
                message: nil,
                attributedContent: payload.attributedContent
            )
        } catch let error as MarkdownDocumentRendererError {
            hostingView.rootView = PreviewRootView(
                title: url.lastPathComponent,
                message: error.errorDescription,
                attributedContent: nil
            )
        } catch {
            hostingView.rootView = PreviewRootView(
                title: url.lastPathComponent,
                message: error.localizedDescription,
                attributedContent: nil
            )
        }
    }
}
```

- [ ] **Step 4: Update the host app status window so it explains the extension and its caveat**

Replace `/MarkdownQuickLookApp/App/StatusView.swift` with:

```swift
import SwiftUI

struct StatusView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Markdown Quick Look")
                .font(.largeTitle.weight(.semibold))

            Text("This app installs a Quick Look Preview Extension that best-effort targets standard .md files.")

            Text("Target content type: net.daringfireball.markdown")
                .font(.system(.body, design: .monospaced))

            Text("Expected caveat: Finder may still keep the built-in plain-text preview on some macOS releases.")
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Local verification")
                    .font(.headline)

                Text("1. Run Scripts/dev-preview.sh")
                Text("2. Open the fixture in Finder")
                Text("3. Press Space to compare Finder's chosen preview")
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}
```

- [ ] **Step 5: Build the app again to verify the extension compiles with the renderer**

Run:

```bash
xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLookApp \
  -destination 'platform=macOS' \
  build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit the extension wiring**

Run:

```bash
git add MarkdownQuickLookApp/App/StatusView.swift MarkdownQuickLookPreviewExtension/MarkdownTextView.swift MarkdownQuickLookPreviewExtension/PreviewRootView.swift MarkdownQuickLookPreviewExtension/PreviewViewController.swift
git commit -m "feat: wire markdown preview extension"
```

### Task 4: Add Fixture, Tooling, And End-To-End Verification Docs

**Files:**
- Create: `/Fixtures/Sample.md`
- Create: `/Scripts/dev-preview.sh`
- Create: `/README.md`

- [ ] **Step 1: Add the manual verification fixture**

Create `/Fixtures/Sample.md`:

````markdown
# Markdown Quick Look

This file checks the app's best-effort preview path for standard `.md` files.

## Checklist

- Heading styling
- Paragraph spacing
- List bullets
- [Link rendering](https://openai.com)

> If Finder still shows plain text, the extension may be registered correctly and macOS may still prefer the built-in preview.

```swift
let greeting = "hello, quick look"
print(greeting)
```
````

- [ ] **Step 2: Add the build and reload helper script**

Create `/Scripts/dev-preview.sh`:

```bash
#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

xcodebuild \
  -project MarkdownQuickLook.xcodeproj \
  -scheme MarkdownQuickLookApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/.derivedData" \
  build

APP_PATH="$ROOT/.derivedData/Build/Products/Debug/MarkdownQuickLookApp.app"

open "$APP_PATH"

sleep 2
qlmanage -r
qlmanage -r cache

echo
echo "Extension registration:"
pluginkit -m -A | rg 'MarkdownQuickLookApp|MarkdownQuickLookPreviewExtension' || true

echo
echo "App bundle:"
echo "  $APP_PATH"

echo
echo "Fixture:"
echo "  $ROOT/Fixtures/Sample.md"

echo
echo "Next steps:"
echo "  1. Open Finder."
echo "  2. Select the fixture file."
echo "  3. Press Space."
echo
echo "If Finder still shows plain text, the extension built correctly but macOS kept the built-in preview path."
```

Run:

```bash
chmod +x Scripts/dev-preview.sh
```

- [ ] **Step 3: Document the local workflow**

Create `/README.md`:

````markdown
# Markdown Quick Look

Best-effort macOS Quick Look preview app for standard Markdown files.

## Requirements

- Xcode 26.1.1 or newer
- XcodeGen 2.45.3 or newer

## Generate the project

```bash
xcodegen generate
open MarkdownQuickLook.xcodeproj
```

## Run the local verification flow

```bash
./Scripts/dev-preview.sh
```

Then:

1. Open Finder
2. Select `Fixtures/Sample.md`
3. Press `Space`

## Expected outcomes

- Success case: Finder uses the app's custom preview for `Fixtures/Sample.md`
- Limitation case: Finder keeps the built-in plain-text preview even though the app and extension built and registered correctly
````

- [ ] **Step 4: Run the full local verification flow**

Run:

```bash
./Scripts/dev-preview.sh
```

Expected:
- The app builds successfully
- The app opens
- Quick Look caches reset
- The script prints the app path, fixture path, and registration output

- [ ] **Step 5: Commit the tooling and docs**

Run:

```bash
git add Fixtures/Sample.md Scripts/dev-preview.sh README.md
git commit -m "docs: add preview verification workflow"
```
