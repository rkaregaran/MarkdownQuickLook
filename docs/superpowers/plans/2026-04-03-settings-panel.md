# Settings Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a settings panel to the host app that lets users adjust text size (7 levels) and font family (3 options) for Markdown Quick Look previews.

**Architecture:** A `MarkdownRenderSettings` value type in the `MarkdownRendering` framework defines the settings model. A `MarkdownSettingsStore` persists settings to a shared app-group `UserDefaults` so the Quick Look extension can read them. The renderer accepts settings as an init parameter and uses them to scale all font sizes and select the font family. The host app's `StatusView` gets inline controls that bind to the store.

**Tech Stack:** Swift, SwiftUI, AppKit (NSFont), UserDefaults with app groups, XcodeGen

---

## File Structure

| File | Role |
|------|------|
| `MarkdownRendering/Sources/MarkdownRenderSettings.swift` | **Create** — Settings struct, TextSizeLevel enum, FontFamily enum |
| `MarkdownRendering/Sources/MarkdownSettingsStore.swift` | **Create** — UserDefaults persistence, ObservableObject |
| `MarkdownRendering/Tests/MarkdownRenderSettingsTests.swift` | **Create** — Tests for model and store |
| `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift` | **Modify** — Accept settings, use scaled sizes and font family |
| `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift` | **Modify** — Add tests for non-default settings |
| `MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements` | **Create** — App group entitlement |
| `MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements` | **Create** — App group entitlement |
| `project.yml` | **Modify** — Add entitlements, add MarkdownRendering dependency to app |
| `MarkdownQuickLookPreviewExtension/PreviewViewController.swift` | **Modify** — Read settings from store, pass to renderer |
| `MarkdownQuickLookApp/App/StatusView.swift` | **Modify** — Add settings controls and preview snippet |

---

### Task 1: Create MarkdownRenderSettings Model

**Files:**
- Create: `MarkdownRendering/Sources/MarkdownRenderSettings.swift`
- Create: `MarkdownRendering/Tests/MarkdownRenderSettingsTests.swift`

- [ ] **Step 1: Write failing tests for the settings model**

Create `MarkdownRendering/Tests/MarkdownRenderSettingsTests.swift`:

```swift
import XCTest
@testable import MarkdownRendering

final class MarkdownRenderSettingsTests: XCTestCase {
    func testDefaultSettingsUseMediumSizeAndSystemFont() {
        let settings = MarkdownRenderSettings.default
        XCTAssertEqual(settings.textSizeLevel, .medium)
        XCTAssertEqual(settings.fontFamily, .system)
    }

    func testMediumScaleFactorIsOne() {
        XCTAssertEqual(TextSizeLevel.medium.scaleFactor, 1.0)
    }

    func testExtraSmallScaleFactorIsPointEight() {
        XCTAssertEqual(TextSizeLevel.extraSmall.scaleFactor, 0.80)
    }

    func testExtraExtraExtraLargeScaleFactorIsOnePointFiveFive() {
        XCTAssertEqual(TextSizeLevel.extraExtraExtraLarge.scaleFactor, 1.55)
    }

    func testTextSizeLevelHasSevenCases() {
        XCTAssertEqual(TextSizeLevel.allCases.count, 7)
    }

    func testScaleFactorsIncreaseMonotonically() {
        let factors = TextSizeLevel.allCases.map(\.scaleFactor)
        for i in 1..<factors.count {
            XCTAssertGreaterThan(factors[i], factors[i - 1])
        }
    }

    func testFontFamilyHasThreeCases() {
        XCTAssertEqual(FontFamily.allCases.count, 3)
    }

    func testSettingsRoundTripsThroughCodable() throws {
        let original = MarkdownRenderSettings(
            textSizeLevel: .extraLarge,
            fontFamily: .serif
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MarkdownRenderSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFontFamilySystemReturnsSystemFont() {
        let font = FontFamily.system.font(ofSize: 15, weight: .regular)
        XCTAssertEqual(font.pointSize, 15)
        XCTAssertFalse(font.isFixedPitch)
    }

    func testFontFamilyMonospacedReturnsFixedPitchFont() {
        let font = FontFamily.monospaced.font(ofSize: 15, weight: .regular)
        XCTAssertEqual(font.pointSize, 15)
        XCTAssertTrue(font.isFixedPitch)
    }

    func testFontFamilySerifReturnsFontWithSerifDesign() {
        let font = FontFamily.serif.font(ofSize: 15, weight: .regular)
        XCTAssertEqual(font.pointSize, 15)
        XCTAssertFalse(font.isFixedPitch)
        // Serif font should differ from system font
        let systemFont = FontFamily.system.font(ofSize: 15, weight: .regular)
        XCTAssertNotEqual(font.fontName, systemFont.fontName)
    }

    func testFontFamilyPreservesWeight() {
        let bold = FontFamily.system.font(ofSize: 15, weight: .semibold)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.bold))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: Compilation failure — `MarkdownRenderSettings`, `TextSizeLevel`, `FontFamily` not found.

- [ ] **Step 3: Write the MarkdownRenderSettings implementation**

Create `MarkdownRendering/Sources/MarkdownRenderSettings.swift`:

```swift
import AppKit

public struct MarkdownRenderSettings: Codable, Equatable, Sendable {
    public var textSizeLevel: TextSizeLevel
    public var fontFamily: FontFamily

    public static let `default` = MarkdownRenderSettings(
        textSizeLevel: .medium,
        fontFamily: .system
    )

    public init(textSizeLevel: TextSizeLevel = .medium, fontFamily: FontFamily = .system) {
        self.textSizeLevel = textSizeLevel
        self.fontFamily = fontFamily
    }
}

public enum TextSizeLevel: Int, Codable, CaseIterable, Sendable {
    case extraSmall = 0
    case small = 1
    case medium = 2
    case large = 3
    case extraLarge = 4
    case extraExtraLarge = 5
    case extraExtraExtraLarge = 6

    public var scaleFactor: CGFloat {
        switch self {
        case .extraSmall: return 0.80
        case .small: return 0.90
        case .medium: return 1.00
        case .large: return 1.10
        case .extraLarge: return 1.25
        case .extraExtraLarge: return 1.40
        case .extraExtraExtraLarge: return 1.55
        }
    }

    public var displayName: String {
        switch self {
        case .extraSmall: return "Extra Small"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        case .extraExtraLarge: return "Extra Extra Large"
        case .extraExtraExtraLarge: return "Extra Extra Extra Large"
        }
    }
}

public enum FontFamily: String, Codable, CaseIterable, Sendable {
    case system
    case serif
    case monospaced

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .serif: return "Serif"
        case .monospaced: return "Mono"
        }
    }

    public func font(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch self {
        case .system:
            return NSFont.systemFont(ofSize: size, weight: weight)
        case .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return NSFont(descriptor: descriptor, size: size) ?? base
            }
            return base
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownRenderSettings.swift MarkdownRendering/Tests/MarkdownRenderSettingsTests.swift
git commit -m "feat: add MarkdownRenderSettings model with text size and font family"
```

---

### Task 2: Create MarkdownSettingsStore

**Files:**
- Create: `MarkdownRendering/Sources/MarkdownSettingsStore.swift`
- Modify: `MarkdownRendering/Tests/MarkdownRenderSettingsTests.swift`

- [ ] **Step 1: Write failing tests for the settings store**

Append to `MarkdownRendering/Tests/MarkdownRenderSettingsTests.swift`:

```swift
final class MarkdownSettingsStoreTests: XCTestCase {
    private let testSuiteName = "com.test.MarkdownSettingsStoreTests.\(UUID().uuidString)"

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: testSuiteName) {
            defaults.removePersistentDomain(forName: testSuiteName)
        }
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: testSuiteName)!
    }

    func testDefaultSettingsWhenNothingStored() {
        let store = MarkdownSettingsStore(defaults: makeDefaults())
        XCTAssertEqual(store.settings, .default)
    }

    func testSettingsPersistAcrossInstances() {
        let defaults = makeDefaults()
        let store1 = MarkdownSettingsStore(defaults: defaults)
        store1.settings = MarkdownRenderSettings(textSizeLevel: .large, fontFamily: .serif)

        let store2 = MarkdownSettingsStore(defaults: defaults)
        XCTAssertEqual(store2.settings.textSizeLevel, .large)
        XCTAssertEqual(store2.settings.fontFamily, .serif)
    }

    func testCorruptedDataFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data([0xFF, 0xFE]), forKey: "renderSettings")

        let store = MarkdownSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, .default)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: Compilation failure — `MarkdownSettingsStore` not found.

- [ ] **Step 3: Write the MarkdownSettingsStore implementation**

Create `MarkdownRendering/Sources/MarkdownSettingsStore.swift`:

```swift
import Combine
import Foundation

public final class MarkdownSettingsStore: ObservableObject {
    private static let settingsKey = "renderSettings"
    static let suiteName = "group.com.rzkr.MarkdownQuickLook"

    private let defaults: UserDefaults

    @Published public var settings: MarkdownRenderSettings {
        didSet { save() }
    }

    public convenience init() {
        let defaults = UserDefaults(suiteName: MarkdownSettingsStore.suiteName) ?? .standard
        self.init(defaults: defaults)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> MarkdownRenderSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(MarkdownRenderSettings.self, from: data)
        else { return .default }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownSettingsStore.swift MarkdownRendering/Tests/MarkdownRenderSettingsTests.swift
git commit -m "feat: add MarkdownSettingsStore for shared UserDefaults persistence"
```

---

### Task 3: Configure App Group Entitlements and Project

**Files:**
- Create: `MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements`
- Create: `MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements`
- Modify: `project.yml`

- [ ] **Step 1: Create the app entitlements file**

Create `MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.rzkr.MarkdownQuickLook</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Create the extension entitlements file**

Create `MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.rzkr.MarkdownQuickLook</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Update project.yml**

Three changes to `project.yml`:

1. Add `CODE_SIGN_ENTITLEMENTS` to the **MarkdownQuickLookApp** target settings and add **MarkdownRendering** dependency:

```yaml
  MarkdownQuickLookApp:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: MarkdownQuickLookApp/App
    settings:
      base:
        PRODUCT_NAME: MarkdownQuickLook
        PRODUCT_BUNDLE_IDENTIFIER: com.rzkr.MarkdownQuickLook.app
        INFOPLIST_FILE: MarkdownQuickLookApp/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_ENTITLEMENTS: MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements
    dependencies:
      - target: MarkdownQuickLookPreviewExtension
        embed: true
      - target: MarkdownRendering
```

2. Add `CODE_SIGN_ENTITLEMENTS` to the **MarkdownQuickLookPreviewExtension** target settings:

```yaml
  MarkdownQuickLookPreviewExtension:
    type: app-extension
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: MarkdownQuickLookPreviewExtension
        excludes:
          - Info.plist
          - Tests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.rzkr.MarkdownQuickLook.app.preview
        INFOPLIST_FILE: MarkdownQuickLookPreviewExtension/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_STYLE: Automatic
        ENABLE_APP_SANDBOX: YES
        ENABLE_USER_SELECTED_FILES: readonly
        CODE_SIGN_ENTITLEMENTS: MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements
    dependencies:
      - target: MarkdownRendering
```

- [ ] **Step 4: Verify the project generates and builds**

Run:
```bash
xcodegen generate && xcodebuild build -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookApp -destination 'platform=macOS'
```
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add MarkdownQuickLookApp/MarkdownQuickLookApp.entitlements MarkdownQuickLookPreviewExtension/MarkdownQuickLookPreviewExtension.entitlements project.yml
git commit -m "feat: add app group entitlements for shared settings"
```

---

### Task 4: Integrate Settings into MarkdownDocumentRenderer

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Write failing tests for settings-aware rendering**

Append these tests to `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`:

```swift
    func testRenderWithLargeTextSizeProducesLargerBodyFont() throws {
        let largeSettings = MarkdownRenderSettings(textSizeLevel: .large, fontFamily: .system)
        let payload = try renderDocument("Hello world", settings: largeSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize, 15 * 1.10, accuracy: 0.01)
    }

    func testRenderWithExtraSmallTextSizeProducesSmallerBodyFont() throws {
        let smallSettings = MarkdownRenderSettings(textSizeLevel: .extraSmall, fontFamily: .system)
        let payload = try renderDocument("Hello world", settings: smallSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize, 15 * 0.80, accuracy: 0.01)
    }

    func testRenderWithSerifFontUsesSerifForBody() throws {
        let serifSettings = MarkdownRenderSettings(textSizeLevel: .medium, fontFamily: .serif)
        let payload = try renderDocument("Hello world", settings: serifSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let systemFont = NSFont.systemFont(ofSize: 15)

        XCTAssertNotEqual(font?.fontName, systemFont.fontName)
    }

    func testRenderWithMonospacedFontUsesFixedPitchForBody() throws {
        let monoSettings = MarkdownRenderSettings(textSizeLevel: .medium, fontFamily: .monospaced)
        let payload = try renderDocument("Hello world", settings: monoSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertTrue(font?.isFixedPitch == true)
    }

    func testRenderCodeBlockStaysMonospacedRegardlessOfFontFamily() throws {
        let serifSettings = MarkdownRenderSettings(textSizeLevel: .medium, fontFamily: .serif)
        let payload = try renderDocument("```\nlet x = 1\n```", settings: serifSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertTrue(font?.isFixedPitch == true)
    }

    func testRenderHeadingScalesWithTextSizeLevel() throws {
        let largeSettings = MarkdownRenderSettings(textSizeLevel: .large, fontFamily: .system)
        let payload = try renderDocument("# Title", settings: largeSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize, 30 * 1.10, accuracy: 0.01)
    }

    func testDefaultSettingsProduceSameFontSizesAsBeforeSettingsFeature() throws {
        let payload = try renderDocument("# Title\n\nBody text\n\n```\ncode\n```").payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString

        let titleRange = nsString.range(of: "Title")
        let bodyRange = nsString.range(of: "Body text")
        let codeRange = nsString.range(of: "code")

        let titleFont = rendered.attribute(.font, at: titleRange.location, effectiveRange: nil) as? NSFont
        let bodyFont = rendered.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont
        let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont

        XCTAssertEqual(titleFont?.pointSize, 30)
        XCTAssertEqual(bodyFont?.pointSize, 15)
        XCTAssertEqual(codeFont?.pointSize, 13)
    }
```

Also update the private `renderDocument` helper to accept optional settings:

```swift
    private func renderDocument(_ contents: String, settings: MarkdownRenderSettings = .default) throws -> (url: URL, payload: MarkdownRenderPayload) {
        let url = try temporaryMarkdownFile(contents)
        defer { try? FileManager.default.removeItem(at: url) }
        let payload = try MarkdownDocumentRenderer(settings: settings).render(fileAt: url)
        return (url, payload)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: Compilation failure — `MarkdownDocumentRenderer(settings:)` does not exist.

- [ ] **Step 3: Implement settings integration in the renderer**

Modify `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`. The changes are:

**Replace the init and LayoutConstants** (lines 46-53):

Replace:
```swift
public final class MarkdownDocumentRenderer {
    private enum LayoutConstants {
        static let lineSpacing: CGFloat = 4
        static let paragraphSpacing: CGFloat = 10
        static let hangingIndent: CGFloat = 24
    }

    public init() {}
```

With:
```swift
public final class MarkdownDocumentRenderer {
    private let settings: MarkdownRenderSettings

    public init(settings: MarkdownRenderSettings = .default) {
        self.settings = settings
    }
```

**Replace `headingBaseFont(for:)`** (lines 398-409):

Replace:
```swift
    private func headingBaseFont(for level: Int) -> NSFont {
        switch level {
        case 1:
            return NSFont.systemFont(ofSize: 30, weight: .semibold)
        case 2:
            return NSFont.systemFont(ofSize: 24, weight: .semibold)
        case 3:
            return NSFont.systemFont(ofSize: 20, weight: .semibold)
        default:
            return NSFont.systemFont(ofSize: 17, weight: .semibold)
        }
    }
```

With:
```swift
    private func headingBaseFont(for level: Int) -> NSFont {
        settings.fontFamily.font(ofSize: headingSize(for: level), weight: .semibold)
    }
```

**Replace `headingFont(for:level:)`** (lines 411-426):

Replace:
```swift
    private func headingFont(for baseFont: NSFont, level: Int) -> NSFont {
        let sizedFont = baseFont.isFixedPitch ? NSFont.monospacedSystemFont(ofSize: headingSize(for: level), weight: .semibold) : NSFont.systemFont(ofSize: headingSize(for: level), weight: .semibold)
```

With:
```swift
    private func headingFont(for baseFont: NSFont, level: Int) -> NSFont {
        let size = headingSize(for: level)
        let sizedFont = baseFont.isFixedPitch ? NSFont.monospacedSystemFont(ofSize: size, weight: .semibold) : settings.fontFamily.font(ofSize: size, weight: .semibold)
```

**Replace `headingSize(for:)`** (lines 428-439):

Replace:
```swift
    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            return 30
        case 2:
            return 24
        case 3:
            return 20
        default:
            return 17
        }
    }
```

With:
```swift
    private func headingSize(for level: Int) -> CGFloat {
        let base: CGFloat
        switch level {
        case 1: base = 30
        case 2: base = 24
        case 3: base = 20
        default: base = 17
        }
        return base * settings.textSizeLevel.scaleFactor
    }
```

**Replace `appendCodeBlock`** (lines 441-449):

Replace:
```swift
    private func appendCodeBlock(_ code: String, to output: NSMutableAttributedString) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
```

With:
```swift
    private func appendCodeBlock(_ code: String, to output: NSMutableAttributedString) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13 * settings.textSizeLevel.scaleFactor, weight: .regular),
```

**Replace `paragraphAttributes()`** (lines 469-475):

Replace:
```swift
    private func paragraphAttributes() -> [NSAttributedString.Key: Any] {
        return [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle()
        ]
    }
```

With:
```swift
    private func paragraphAttributes() -> [NSAttributedString.Key: Any] {
        return [
            .font: settings.fontFamily.font(ofSize: 15 * settings.textSizeLevel.scaleFactor, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle()
        ]
    }
```

**Replace `bodyParagraphStyle()`** (lines 485-490):

Replace:
```swift
    private func bodyParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = LayoutConstants.lineSpacing
        paragraph.paragraphSpacing = LayoutConstants.paragraphSpacing
        return paragraph
    }
```

With:
```swift
    private func bodyParagraphStyle() -> NSMutableParagraphStyle {
        let scale = settings.textSizeLevel.scaleFactor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4 * scale
        paragraph.paragraphSpacing = 10 * scale
        return paragraph
    }
```

**Replace `hangingIndentParagraphStyle()`** (lines 492-497):

Replace:
```swift
    private func hangingIndentParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = bodyParagraphStyle()
        paragraph.firstLineHeadIndent = LayoutConstants.hangingIndent
        paragraph.headIndent = LayoutConstants.hangingIndent
        return paragraph
    }
```

With:
```swift
    private func hangingIndentParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = bodyParagraphStyle()
        let indent = 24 * settings.textSizeLevel.scaleFactor
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        return paragraph
    }
```

**Replace `hangingIndentAttributes(foregroundColor:)`** (lines 499-505):

Replace:
```swift
    private func hangingIndentAttributes(foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: foregroundColor,
            .paragraphStyle: hangingIndentParagraphStyle()
        ]
    }
```

With:
```swift
    private func hangingIndentAttributes(foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: settings.fontFamily.font(ofSize: 15 * settings.textSizeLevel.scaleFactor, weight: .regular),
            .foregroundColor: foregroundColor,
            .paragraphStyle: hangingIndentParagraphStyle()
        ]
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: All tests PASS (including all existing tests, since default settings produce identical output).

- [ ] **Step 5: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: integrate render settings into MarkdownDocumentRenderer"
```

---

### Task 5: Wire Settings in PreviewViewController

**Files:**
- Modify: `MarkdownQuickLookPreviewExtension/PreviewViewController.swift:159-164`

- [ ] **Step 1: Update the renderPayload method to read settings**

In `PreviewViewController.swift`, replace the `renderPayload` method (lines 159-164):

Replace:
```swift
    private static func renderPayload(
        for document: MarkdownPreparedDocument,
        shouldContinue: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> MarkdownRenderPayload {
        try await MarkdownDocumentRenderer().render(document: document, shouldContinue: shouldContinue)
    }
```

With:
```swift
    private static func renderPayload(
        for document: MarkdownPreparedDocument,
        shouldContinue: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> MarkdownRenderPayload {
        let settings = MarkdownSettingsStore().settings
        return try await MarkdownDocumentRenderer(settings: settings).render(document: document, shouldContinue: shouldContinue)
    }
```

- [ ] **Step 2: Run extension tests to verify nothing broke**

Run:
```bash
xcodegen generate && xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
```
Expected: All existing tests PASS (they inject custom renderProviders and don't hit this code path).

- [ ] **Step 3: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/PreviewViewController.swift
git commit -m "feat: read render settings from store in Quick Look extension"
```

---

### Task 6: Build Settings UI in StatusView

**Files:**
- Modify: `MarkdownQuickLookApp/App/StatusView.swift`

- [ ] **Step 1: Update StatusView with settings controls**

Replace the entire contents of `MarkdownQuickLookApp/App/StatusView.swift`:

```swift
import MarkdownRendering
import SwiftUI

struct StatusView: View {
    private let experience = InstallExperience.current()
    @ObservedObject private var settingsStore = MarkdownSettingsStore()

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

- [ ] **Step 2: Verify the app builds and all tests pass**

Run:
```bash
xcodegen generate && xcodebuild build -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookApp -destination 'platform=macOS'
```
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add MarkdownQuickLookApp/App/StatusView.swift
git commit -m "feat: add text size and font settings controls to StatusView"
```

---

### Task 7: Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Run all three test suites**

Run:
```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```
Expected: All three suites PASS.

- [ ] **Step 2: Build the release artifact**

Run:
```bash
./Scripts/build-release.sh
```
Expected: Release build succeeds.

- [ ] **Step 3: Manual smoke test**

Run:
```bash
./Scripts/dev-preview.sh
```

Verify:
1. Host app opens and shows install status + settings section
2. Text size slider has 7 stops and displays level name
3. Font picker shows System / Serif / Mono segments
4. Preview snippet updates live when changing settings
5. Select a .md file in Finder, press Space — Quick Look preview renders with chosen settings
