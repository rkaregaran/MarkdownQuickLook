# TOC Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a left-side table of contents sidebar to the Markdown Quick Look preview, with click-to-scroll, scroll-spy active highlighting, and a chevron toggle whose state persists across previews.

**Architecture:** The renderer in `MarkdownRendering` is extended to emit `HeadingAnchor` values (level + text + `NSRange` into the rendered `NSAttributedString`). The preview extension owns a `TableOfContentsViewModel` (`ObservableObject`) that filters to h1–h3, manages collapsed state via App Group `UserDefaults`, and tracks the active anchor. `PreviewRootView` lays out an `HStack { sidebar | divider | content }`. `MarkdownTextView` gains a `Coordinator` that observes `NSClipView` bounds changes, computes per-anchor y-positions through the `NSLayoutManager`, and drives `activeAnchorIndex` plus programmatic scrolls.

**Tech Stack:** Swift 5+, SwiftUI, AppKit (`NSTextView`, `NSScrollView`, `NSLayoutManager`), XcodeGen (`project.yml`), XCTest, macOS 14.0+.

**Spec:** `docs/superpowers/specs/2026-05-03-toc-sidebar-design.md`

---

## Conventions for every task

- Run `xcodegen generate` after any `project.yml` change before building or testing.
- Run targeted test suite via:
  ```bash
  xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme <Scheme> -destination 'platform=macOS'
  ```
- Commit with a conventional-commit prefix (`feat:`, `test:`, `refactor:`, etc.) and the Co-Authored-By footer used by previous commits.
- Keep tasks isolated: each task ends green (all three test schemes pass) and committed.

---

## Task 1: Add `HeadingAnchor` type and `tableOfContents` field on `MarkdownRenderPayload`

**Files:**
- Create: `MarkdownRendering/Sources/HeadingAnchor.swift`
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift` (lines 4–12 — `MarkdownRenderPayload`)
- Test: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift` (append at end)

- [ ] **Step 1: Write the failing test**

Append to `MarkdownDocumentRendererTests.swift` just before the trailing `}` of the class (after `testRenderWithExtraSmallTextSizeProducesSmallerBodyFont` and friends — find the end of the class, insert before final `}`):

```swift
func testRenderEmitsEmptyTableOfContentsForDocumentWithoutHeadings() throws {
    let payload = try renderDocument("Just a paragraph, no headings here.").payload
    XCTAssertEqual(payload.tableOfContents, [])
}
```

- [ ] **Step 2: Run the test — expect compile failure**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: build error — `value of type 'MarkdownRenderPayload' has no member 'tableOfContents'` (and `HeadingAnchor` is referenced indirectly via `[]` literal inference; the bare assertion against `[]` may compile only after the field exists, but we'll add the type first).

- [ ] **Step 3: Create `HeadingAnchor.swift`**

Create `MarkdownRendering/Sources/HeadingAnchor.swift` with this exact content:

```swift
import Foundation

public struct HeadingAnchor: Equatable, Sendable {
    public let level: Int
    public let text: String
    public let range: NSRange

    public init(level: Int, text: String, range: NSRange) {
        self.level = level
        self.text = text
        self.range = range
    }
}
```

- [ ] **Step 4: Extend `MarkdownRenderPayload`**

In `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`, replace lines 4–12 with:

```swift
public struct MarkdownRenderPayload {
    public let title: String
    public let attributedContent: NSAttributedString
    public let tableOfContents: [HeadingAnchor]

    public init(
        title: String,
        attributedContent: NSAttributedString,
        tableOfContents: [HeadingAnchor] = []
    ) {
        self.title = title
        self.attributedContent = attributedContent
        self.tableOfContents = tableOfContents
    }
}
```

The default `[]` for `tableOfContents` keeps every existing call site (tests, controller stubs) compiling unchanged.

- [ ] **Step 5: Run the test — expect pass**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: PASS. The two existing render functions still construct payloads without specifying `tableOfContents`, so they default to `[]`, which matches the assertion.

- [ ] **Step 6: Commit**

```bash
git add MarkdownRendering/Sources/HeadingAnchor.swift MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "$(cat <<'EOF'
feat: add HeadingAnchor type and table-of-contents field on MarkdownRenderPayload

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Collect heading anchors during both `render` overloads

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift` (lines 87–128 — both `render` functions)
- Test: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Write the failing tests**

Append three tests to `MarkdownDocumentRendererTests.swift` next to the test added in Task 1:

```swift
func testRenderEmitsAnchorForEachHeadingInDocumentOrder() throws {
    let payload = try renderDocument(
        """
        # Top level
        Body.

        ## Second
        More body.

        ### Third
        Final body.
        """
    ).payload

    XCTAssertEqual(payload.tableOfContents.map(\.level), [1, 2, 3])
    XCTAssertEqual(payload.tableOfContents.map(\.text), ["Top level", "Second", "Third"])

    let locations = payload.tableOfContents.map(\.range.location)
    XCTAssertEqual(locations, locations.sorted(), "Anchors must be in document order")
}

func testRenderEmitsAllSixHeadingLevels() throws {
    let payload = try renderDocument(
        """
        # H1

        ## H2

        ### H3

        #### H4

        ##### H5

        ###### H6
        """
    ).payload

    XCTAssertEqual(payload.tableOfContents.map(\.level), [1, 2, 3, 4, 5, 6])
}

func testRenderAnchorRangeMatchesHeadingPositionInRenderedString() throws {
    let payload = try renderDocument(
        """
        Intro paragraph.

        # First Heading

        Some body text after the heading.

        ## Second Heading

        More text.
        """
    ).payload

    let rendered = payload.attributedContent.string as NSString
    XCTAssertEqual(payload.tableOfContents.count, 2)

    for anchor in payload.tableOfContents {
        let snippet = rendered.substring(with: NSRange(location: anchor.range.location, length: anchor.text.count))
        XCTAssertEqual(snippet, anchor.text, "Anchor for level \(anchor.level) should land on its heading text")
    }
}
```

- [ ] **Step 2: Run the tests — expect failures**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: the three new tests FAIL with empty `tableOfContents`. All other tests PASS.

- [ ] **Step 3: Implement anchor collection in the synchronous `render`**

In `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`, replace the body of `render(document:)` (lines 87–103) with:

```swift
@MainActor
public func render(document: MarkdownPreparedDocument) -> MarkdownRenderPayload {
    let formatted = NSMutableAttributedString()
    var anchors: [HeadingAnchor] = []

    for (index, block) in document.blocks.enumerated() {
        if case .heading(let level, let text) = block {
            anchors.append(
                HeadingAnchor(
                    level: level,
                    text: text,
                    range: NSRange(location: formatted.length, length: 0)
                )
            )
        }
        append(block, to: formatted, baseURL: document.baseURL)

        if index < document.blocks.count - 1 {
            formatted.append(NSAttributedString(string: "\n\n"))
        }
    }

    return MarkdownRenderPayload(
        title: document.title,
        attributedContent: NSAttributedString(attributedString: formatted),
        tableOfContents: anchors
    )
}
```

- [ ] **Step 4: Implement anchor collection in the async `render`**

Replace the body of `render(document:shouldContinue:)` (lines 105–128) with:

```swift
@MainActor
public func render(
    document: MarkdownPreparedDocument,
    shouldContinue: @escaping @MainActor @Sendable () -> Bool
) async throws -> MarkdownRenderPayload {
    let formatted = NSMutableAttributedString()
    var anchors: [HeadingAnchor] = []

    for (index, block) in document.blocks.enumerated() {
        try ensureRenderingCanContinue(shouldContinue)
        if case .heading(let level, let text) = block {
            anchors.append(
                HeadingAnchor(
                    level: level,
                    text: text,
                    range: NSRange(location: formatted.length, length: 0)
                )
            )
        }
        append(block, to: formatted, baseURL: document.baseURL)

        if index < document.blocks.count - 1 {
            formatted.append(NSAttributedString(string: "\n\n"))
            await Task.yield()
        }
    }

    try ensureRenderingCanContinue(shouldContinue)

    return MarkdownRenderPayload(
        title: document.title,
        attributedContent: NSAttributedString(attributedString: formatted),
        tableOfContents: anchors
    )
}
```

- [ ] **Step 5: Run the tests — expect pass**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: all tests PASS, including the three new ones.

- [ ] **Step 6: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "$(cat <<'EOF'
feat: emit heading anchors with NSRange offsets during markdown render

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Fixture-based anchor tests

**Files:**
- Test: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add fixture assertions**

Append two tests near the others. The fixture path is relative to `Bundle.main.bundleURL` — but the test target is hostless, so we read the fixture by absolute path computed from `#filePath`:

```swift
func testTableOfContentsForSampleFixture() throws {
    let fixtureURL = sampleFixtureURL(named: "Sample.md")
    let payload = try MarkdownDocumentRenderer().render(fileAt: fixtureURL)

    let levels = payload.tableOfContents.map(\.level)
    let texts = payload.tableOfContents.map(\.text)

    XCTAssertEqual(levels, [1, 2, 2, 2, 2, 2])
    XCTAssertEqual(
        texts,
        [
            "Markdown Quick Look",
            "Checklist",
            "Features",
            "Ordered Steps",
            "Nested Lists",
            "Image Test"
        ]
    )

    let rendered = payload.attributedContent.string as NSString
    for anchor in payload.tableOfContents {
        let snippet = rendered.substring(
            with: NSRange(location: anchor.range.location, length: anchor.text.count)
        )
        XCTAssertEqual(snippet, anchor.text)
    }
}

func testTableOfContentsForShowcaseFixture() throws {
    let fixtureURL = sampleFixtureURL(named: "Showcase.md")
    let payload = try MarkdownDocumentRenderer().render(fileAt: fixtureURL)

    XCTAssertEqual(payload.tableOfContents.count, 5)
    XCTAssertEqual(payload.tableOfContents.first?.level, 1)
    XCTAssertEqual(
        payload.tableOfContents.dropFirst().map(\.level),
        [2, 2, 2, 2]
    )
}

private func sampleFixtureURL(named filename: String, file: StaticString = #filePath) -> URL {
    // Walk up from this test file to repo root, then into Fixtures/.
    let testFile = URL(fileURLWithPath: String(describing: file))
    let repoRoot = testFile
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // MarkdownRendering/
        .deletingLastPathComponent() // repo root
    return repoRoot.appendingPathComponent("Fixtures").appendingPathComponent(filename)
}
```

- [ ] **Step 2: Verify fixture filenames and headings still match**

If `Fixtures/Sample.md` or `Fixtures/Showcase.md` have changed since this plan was written, adjust the expected `texts`/`levels` arrays in the assertions to reflect the current file. Verify by running:

```bash
grep "^#" Fixtures/Sample.md
grep "^#" Fixtures/Showcase.md
```

The expected arrays must match the actual heading lines, in order, with leading `#` markers stripped.

- [ ] **Step 3: Run tests — expect pass**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "$(cat <<'EOF'
test: cover heading anchor extraction against Sample and Showcase fixtures

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `TableOfContentsViewModel` — anchors, displayable filter, visibility

**Files:**
- Create: `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift`
- Create: `MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift`
- Modify: `project.yml` (add the view-model file to the preview-extension test target's source list)

- [ ] **Step 1: Create the view model with the minimum surface needed for filter + visibility**

Create `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift`:

```swift
import Combine
import Foundation
import MarkdownRendering

final class TableOfContentsViewModel: ObservableObject {
    @Published private(set) var displayableAnchors: [HeadingAnchor] = []
    @Published var activeAnchorIndex: Int?
    @Published var collapsed: Bool = false

    var scrollHandler: ((Int) -> Void)?

    var hasEnoughHeadings: Bool { displayableAnchors.count >= 2 }
    var shouldShowSidebar: Bool { hasEnoughHeadings && !collapsed }
    var shouldShowExpandStrip: Bool { hasEnoughHeadings && collapsed }

    func setAnchors(_ anchors: [HeadingAnchor]) {
        displayableAnchors = anchors.filter { $0.level <= 3 }
        if let active = activeAnchorIndex, active >= displayableAnchors.count {
            activeAnchorIndex = nil
        }
    }

    func requestScroll(to displayIndex: Int) {
        guard displayableAnchors.indices.contains(displayIndex) else { return }
        activeAnchorIndex = displayIndex
        scrollHandler?(displayIndex)
    }
}
```

`Combine` import is included now to keep the file's import block stable for later steps that add persistence wiring.

- [ ] **Step 2: Add the file to the preview-extension test target sources**

Open `project.yml`. Find the `MarkdownQuickLookPreviewExtensionTests` target's `sources:` block (it lists per-file entries). Add this line in the same indentation, alphabetical-ish near the other `MarkdownQuickLookPreviewExtension/*.swift` lines:

```yaml
      - path: MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift
```

The block should now include the existing six files plus this new one. Run:

```bash
xcodegen generate
```

- [ ] **Step 3: Write failing tests**

Create `MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift`:

```swift
import MarkdownRendering
import XCTest
@testable import MarkdownQuickLookPreviewExtension

@MainActor
final class TableOfContentsViewModelTests: XCTestCase {
    func testDisplayableAnchorsFiltersToHThreeAndAbove() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([
            anchor(level: 1),
            anchor(level: 2),
            anchor(level: 3),
            anchor(level: 4),
            anchor(level: 5)
        ])

        XCTAssertEqual(viewModel.displayableAnchors.map(\.level), [1, 2, 3])
    }

    func testVisibilityForEmptyHeadings() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([])

        XCTAssertFalse(viewModel.shouldShowSidebar)
        XCTAssertFalse(viewModel.shouldShowExpandStrip)
    }

    func testVisibilityForSingleHeading() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1)])

        XCTAssertFalse(viewModel.shouldShowSidebar)
        XCTAssertFalse(viewModel.shouldShowExpandStrip)
    }

    func testVisibilityWhenExpandedAndCollapsed() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])

        XCTAssertTrue(viewModel.shouldShowSidebar)
        XCTAssertFalse(viewModel.shouldShowExpandStrip)

        viewModel.collapsed = true

        XCTAssertFalse(viewModel.shouldShowSidebar)
        XCTAssertTrue(viewModel.shouldShowExpandStrip)
    }

    func testVisibilityIgnoresLevelsBelowThree() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 4), anchor(level: 5), anchor(level: 6)])

        XCTAssertFalse(viewModel.shouldShowSidebar)
        XCTAssertFalse(viewModel.shouldShowExpandStrip)
    }

    func testActiveAnchorIndexClampsWhenAnchorsShrink() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2), anchor(level: 3)])
        viewModel.activeAnchorIndex = 2

        viewModel.setAnchors([anchor(level: 1)])

        XCTAssertNil(viewModel.activeAnchorIndex)
    }

    func testRequestScrollInvokesHandlerAndUpdatesActiveIndex() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])

        var receivedIndex: Int?
        viewModel.scrollHandler = { receivedIndex = $0 }

        viewModel.requestScroll(to: 1)

        XCTAssertEqual(receivedIndex, 1)
        XCTAssertEqual(viewModel.activeAnchorIndex, 1)
    }

    func testRequestScrollIgnoresOutOfBoundsIndex() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])

        var handlerCalls = 0
        viewModel.scrollHandler = { _ in handlerCalls += 1 }

        viewModel.requestScroll(to: 5)

        XCTAssertEqual(handlerCalls, 0)
        XCTAssertNil(viewModel.activeAnchorIndex)
    }

    private func anchor(level: Int, location: Int = 0) -> HeadingAnchor {
        HeadingAnchor(level: level, text: "H\(level)", range: NSRange(location: location, length: 0))
    }
}
```

- [ ] **Step 4: Run the tests — expect pass**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
```
Expected: all eight new tests PASS, no other regressions.

- [ ] **Step 5: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift project.yml
git commit -m "$(cat <<'EOF'
feat: add TableOfContentsViewModel with filter and visibility state

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Persist `collapsed` flag through App Group `UserDefaults`

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownSettingsStore.swift` (line 6 — make `suiteName` public)
- Modify: `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift`
- Modify: `MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift`

- [ ] **Step 1: Expose the App Group suite name from `MarkdownRendering`**

In `MarkdownRendering/Sources/MarkdownSettingsStore.swift`, change line 6 from:

```swift
    static let suiteName = "group.com.rzkr.MarkdownQuickLook"
```

to:

```swift
    public static let suiteName = "group.com.rzkr.MarkdownQuickLook"
```

Leave `settingsKey` package-internal — it's only used by the store itself.

- [ ] **Step 2: Write a failing persistence test**

Append to `TableOfContentsViewModelTests.swift`:

```swift
func testCollapsedFlagPersistsThroughInjectedDefaults() {
    let suite = "test.toc.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        return XCTFail("Failed to create test UserDefaults suite")
    }
    defer {
        defaults.removePersistentDomain(forName: suite)
    }

    let first = TableOfContentsViewModel(defaults: defaults)
    first.collapsed = true

    let second = TableOfContentsViewModel(defaults: defaults)
    XCTAssertTrue(second.collapsed)
}

func testCollapsedFlagDefaultsToFalseInFreshDefaults() {
    let suite = "test.toc.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        return XCTFail("Failed to create test UserDefaults suite")
    }
    defer {
        defaults.removePersistentDomain(forName: suite)
    }

    let viewModel = TableOfContentsViewModel(defaults: defaults)
    XCTAssertFalse(viewModel.collapsed)
}
```

- [ ] **Step 3: Run the tests — expect compile failure**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
```
Expected: build error — `TableOfContentsViewModel` has no `init(defaults:)`.

- [ ] **Step 4: Add persistence to the view model**

Replace the entirety of `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift` with:

```swift
import Combine
import Foundation
import MarkdownRendering

final class TableOfContentsViewModel: ObservableObject {
    static let collapsedDefaultsKey = "tableOfContentsCollapsed"

    @Published private(set) var displayableAnchors: [HeadingAnchor] = []
    @Published var activeAnchorIndex: Int?
    @Published var collapsed: Bool {
        didSet {
            guard collapsed != oldValue else { return }
            defaults.set(collapsed, forKey: Self.collapsedDefaultsKey)
        }
    }

    var scrollHandler: ((Int) -> Void)?

    private let defaults: UserDefaults

    convenience init() {
        let defaults = UserDefaults(suiteName: MarkdownSettingsStore.suiteName) ?? .standard
        self.init(defaults: defaults)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.collapsed = defaults.bool(forKey: Self.collapsedDefaultsKey)
    }

    var hasEnoughHeadings: Bool { displayableAnchors.count >= 2 }
    var shouldShowSidebar: Bool { hasEnoughHeadings && !collapsed }
    var shouldShowExpandStrip: Bool { hasEnoughHeadings && collapsed }

    func setAnchors(_ anchors: [HeadingAnchor]) {
        displayableAnchors = anchors.filter { $0.level <= 3 }
        if let active = activeAnchorIndex, active >= displayableAnchors.count {
            activeAnchorIndex = nil
        }
    }

    func requestScroll(to displayIndex: Int) {
        guard displayableAnchors.indices.contains(displayIndex) else { return }
        activeAnchorIndex = displayIndex
        scrollHandler?(displayIndex)
    }
}
```

- [ ] **Step 5: Run the tests — expect pass**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```
Expected: PASS for both. The rendering test suite is included to catch any breakage from making `suiteName` public.

- [ ] **Step 6: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownSettingsStore.swift MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: persist TOC collapsed flag in App Group UserDefaults

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Pure-function active-anchor activation rule

**Files:**
- Modify: `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift`
- Modify: `MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `TableOfContentsViewModelTests.swift`:

```swift
func testActiveAnchorIndexIsNilForEmptyAnchors() {
    let result = TableOfContentsViewModel.computeActiveAnchorIndex(
        visibleTop: 0,
        anchorYPositions: []
    )
    XCTAssertNil(result)
}

func testActiveAnchorIndexHighlightsFirstWhenScrolledAboveAllAnchors() {
    let result = TableOfContentsViewModel.computeActiveAnchorIndex(
        visibleTop: 0,
        anchorYPositions: [100, 200, 300]
    )
    XCTAssertEqual(result, 0)
}

func testActiveAnchorIndexPicksLastAnchorAtOrAboveThreshold() {
    let result = TableOfContentsViewModel.computeActiveAnchorIndex(
        visibleTop: 250,
        anchorYPositions: [100, 200, 300]
    )
    XCTAssertEqual(result, 1)
}

func testActiveAnchorIndexUsesActivationOffset() {
    // visibleTop = 90, threshold = 90 + 24 = 114; anchor at 100 is "current".
    let result = TableOfContentsViewModel.computeActiveAnchorIndex(
        visibleTop: 90,
        anchorYPositions: [100, 300]
    )
    XCTAssertEqual(result, 0)
}

func testActiveAnchorIndexPastLastAnchorPicksLast() {
    let result = TableOfContentsViewModel.computeActiveAnchorIndex(
        visibleTop: 9_999,
        anchorYPositions: [100, 200, 300]
    )
    XCTAssertEqual(result, 2)
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
```
Expected: `TableOfContentsViewModel` has no `computeActiveAnchorIndex(...)` static method.

- [ ] **Step 3: Add the static activation rule**

Append inside the body of `TableOfContentsViewModel` (just before the closing `}`):

```swift
static let activationOffset: CGFloat = 24

static func computeActiveAnchorIndex(
    visibleTop: CGFloat,
    anchorYPositions: [CGFloat],
    activationOffset: CGFloat = TableOfContentsViewModel.activationOffset
) -> Int? {
    guard anchorYPositions.isEmpty == false else { return nil }
    let cutoff = visibleTop + activationOffset
    if let lastBelow = anchorYPositions.lastIndex(where: { $0 <= cutoff }) {
        return lastBelow
    }
    return 0
}
```

`CoreGraphics.CGFloat` is reachable via the existing `Foundation` import on macOS, so no new import is needed.

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
```
Expected: all five new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: add scroll-spy activation rule on TableOfContentsViewModel

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Wire the view model into `PreviewViewController` and `PreviewRootView` (no sidebar UI yet)

This task plumbs the view model through without rendering the sidebar. The HStack layout and sidebar SwiftUI views come in Tasks 8–9. Splitting this way keeps each commit small and tests passing.

**Files:**
- Modify: `MarkdownQuickLookPreviewExtension/PreviewRootView.swift`
- Modify: `MarkdownQuickLookPreviewExtension/PreviewViewController.swift`
- Modify: `MarkdownQuickLookPreviewExtension/MarkdownTextView.swift` (accept `tocViewModel`)
- Modify: `MarkdownQuickLookPreviewExtension/Tests/PreviewViewControllerTests.swift` (existing tests need the new property if we read it; check no breakage)

- [ ] **Step 1: Update `PreviewRootView` to accept the view model**

Replace the entire contents of `MarkdownQuickLookPreviewExtension/PreviewRootView.swift` with:

```swift
import AppKit
import SwiftUI

struct PreviewRootView: View {
    let title: String
    let message: String?
    let attributedContent: NSAttributedString?
    @ObservedObject var tocViewModel: TableOfContentsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            if let attributedContent {
                MarkdownTextView(attributedText: attributedContent, tocViewModel: tocViewModel)
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

- [ ] **Step 2: Update `MarkdownTextView` to accept the view model (no behavior change yet)**

Replace `MarkdownQuickLookPreviewExtension/MarkdownTextView.swift` with:

```swift
import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    @ObservedObject var tocViewModel: TableOfContentsViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributedText)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
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

(The `tocViewModel` property is added but not yet consumed; coordinator wiring lands in Task 10.)

- [ ] **Step 3: Update `PreviewViewController` to own a view model and pass it through**

Open `MarkdownQuickLookPreviewExtension/PreviewViewController.swift`. Make these edits:

1. After the `private let renderProvider: RenderProvider` declaration (around line 19), add:
   ```swift
   private let tocViewModel = TableOfContentsViewModel()
   ```

2. Replace the `hostingView` initializer (line 14–16):
   ```swift
   private let hostingView = NSHostingView(
       rootView: PreviewRootView(title: "Markdown Preview", message: "Loading preview...", attributedContent: nil)
   )
   ```
   With a lazy initializer that captures `tocViewModel`. Move `hostingView` from a stored property to a `lazy var` because the rootView needs `self.tocViewModel`:
   ```swift
   private lazy var hostingView: NSHostingView<PreviewRootView> = NSHostingView(
       rootView: PreviewRootView(
           title: "Markdown Preview",
           message: "Loading preview...",
           attributedContent: nil,
           tocViewModel: tocViewModel
       )
   )
   ```

3. Update the four call sites that build a `PreviewRootView` (in `loadingRootView(for:)` and the three branches of `preparePreviewOfFile(at:)` — `.prepared`, `.rendererError`, `.failure`). Each one needs `tocViewModel: tocViewModel` as the final argument.

   The full file should now use these constructions:

   ```swift
   private func loadingRootView(for url: URL) -> PreviewRootView {
       PreviewRootView(
           title: url.lastPathComponent,
           message: "Loading preview...",
           attributedContent: nil,
           tocViewModel: tocViewModel
       )
   }
   ```

   For the success branch (replace the existing `hostingView.rootView = PreviewRootView(...)` block in the `.prepared` case):
   ```swift
   tocViewModel.setAnchors(payload.tableOfContents)
   hostingView.rootView = PreviewRootView(
       title: payload.title,
       message: nil,
       attributedContent: payload.attributedContent,
       tocViewModel: tocViewModel
   )
   ```

   For both error branches:
   ```swift
   tocViewModel.setAnchors([])
   hostingView.rootView = PreviewRootView(
       title: url.lastPathComponent,
       message: error.errorDescription,
       attributedContent: nil,
       tocViewModel: tocViewModel
   )
   ```
   …and the analogous change in the `.failure` branch with `message: message`.

   Calling `setAnchors([])` on errors clears any state from a previous successful preview, which keeps the sidebar from lingering when the user moves from a richly-headed file to a broken one.

- [ ] **Step 4: Verify existing controller tests still pass**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
```
Expected: PASS. Existing tests construct `PreviewRootView` indirectly via `controller.testingCurrentRootView` and read `title`, `attributedContent`, `message` — none of those changed names.

- [ ] **Step 5: Build the host app to confirm extension still compiles**

```bash
xcodebuild build -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookApp -destination 'platform=macOS' -configuration Debug
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/PreviewRootView.swift MarkdownQuickLookPreviewExtension/PreviewViewController.swift MarkdownQuickLookPreviewExtension/MarkdownTextView.swift
git commit -m "$(cat <<'EOF'
feat: thread TableOfContentsViewModel through preview view hierarchy

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Build `TableOfContentsSidebar` and `SidebarExpandStrip` SwiftUI views

These views are visual; we build them and verify by compilation. Behavior verification happens in Task 11 manual checks.

**Files:**
- Create: `MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift`
- Modify: `project.yml` (add the new file to the test target source list, so `PreviewRootView` can reference it from tests in Task 9)

- [ ] **Step 1: Create the sidebar views**

Create `MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift`:

```swift
import MarkdownRendering
import SwiftUI

struct TableOfContentsSidebar: View {
    @ObservedObject var viewModel: TableOfContentsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.6))
    }

    private var header: some View {
        HStack {
            Text("Contents")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Button {
                viewModel.collapsed = true
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide table of contents")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.displayableAnchors.enumerated()), id: \.offset) { index, anchor in
                    TableOfContentsRow(
                        anchor: anchor,
                        isActive: viewModel.activeAnchorIndex == index
                    ) {
                        viewModel.requestScroll(to: index)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct TableOfContentsRow: View {
    let anchor: HeadingAnchor
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 3)
                Text(displayText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .padding(.leading, indent)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
            .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .help(anchor.text)
        .onHover { isHovering = $0 }
    }

    private var indent: CGFloat {
        CGFloat(max(anchor.level - 1, 0)) * 12
    }

    private var displayText: AttributedString {
        if let parsed = try? AttributedString(markdown: anchor.text) {
            return parsed
        }
        return AttributedString(anchor.text)
    }
}

struct SidebarExpandStrip: View {
    let action: () -> Void

    var body: some View {
        VStack {
            Button(action: action) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .help("Show table of contents")
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.6))
    }
}
```

- [ ] **Step 2: Add the sidebar file to the test target sources**

In `project.yml`, append another line under the `MarkdownQuickLookPreviewExtensionTests` `sources:` block:

```yaml
      - path: MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift
```

Then:

```bash
xcodegen generate
```

- [ ] **Step 3: Build the host app to confirm the new file compiles**

```bash
xcodebuild build -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookApp -destination 'platform=macOS' -configuration Debug
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run all preview-extension tests to confirm no regression**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift project.yml
git commit -m "$(cat <<'EOF'
feat: add TableOfContentsSidebar and SidebarExpandStrip SwiftUI views

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Compose sidebar into `PreviewRootView` HStack

**Files:**
- Modify: `MarkdownQuickLookPreviewExtension/PreviewRootView.swift`

- [ ] **Step 1: Replace the body with the new HStack layout**

Open `MarkdownQuickLookPreviewExtension/PreviewRootView.swift` and replace its full contents with:

```swift
import AppKit
import SwiftUI

struct PreviewRootView: View {
    let title: String
    let message: String?
    let attributedContent: NSAttributedString?
    @ObservedObject var tocViewModel: TableOfContentsViewModel

    var body: some View {
        HStack(spacing: 0) {
            if tocViewModel.shouldShowSidebar {
                TableOfContentsSidebar(viewModel: tocViewModel)
                    .frame(width: 220)
                Divider()
            } else if tocViewModel.shouldShowExpandStrip {
                SidebarExpandStrip {
                    tocViewModel.collapsed = false
                }
                .frame(width: 28)
                Divider()
            }

            contentColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: tocViewModel.shouldShowSidebar)
        .animation(.easeInOut(duration: 0.18), value: tocViewModel.shouldShowExpandStrip)
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            if let attributedContent {
                MarkdownTextView(attributedText: attributedContent, tocViewModel: tocViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(message ?? "No preview available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
    }
}
```

- [ ] **Step 2: Verify all tests still pass**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```
Expected: PASS.

- [ ] **Step 3: Build the host app**

```bash
xcodebuild build -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookApp -destination 'platform=macOS' -configuration Debug
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/PreviewRootView.swift
git commit -m "$(cat <<'EOF'
feat: lay out preview with table-of-contents sidebar in HStack

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `MarkdownTextView.Coordinator` — scroll-spy and click-to-scroll

This task adds AppKit-side wiring: a coordinator that observes scroll, recomputes anchor y-positions, drives `activeAnchorIndex`, and handles programmatic scroll requests. UI behavior is verified manually in Task 11.

**Files:**
- Modify: `MarkdownQuickLookPreviewExtension/MarkdownTextView.swift`

- [ ] **Step 1: Replace `MarkdownTextView.swift` with the coordinator-aware version**

Replace the full contents of `MarkdownQuickLookPreviewExtension/MarkdownTextView.swift` with:

```swift
import AppKit
import Combine
import MarkdownRendering
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    @ObservedObject var tocViewModel: TableOfContentsViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: tocViewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributedText)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.textStorage?.setAttributedString(attributedText)
        context.coordinator.viewModel = tocViewModel
        context.coordinator.recomputeAnchorPositions()
    }

    final class Coordinator: NSObject {
        var viewModel: TableOfContentsViewModel {
            didSet { wireScrollHandler() }
        }
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        private(set) var anchorYPositions: [CGFloat] = []
        private var suppressScrollSpyUntil: Date?

        init(viewModel: TableOfContentsViewModel) {
            self.viewModel = viewModel
            super.init()
            wireScrollHandler()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView

            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            // Initial layout pass so anchor positions are available immediately.
            DispatchQueue.main.async { [weak self] in
                self?.recomputeAnchorPositions()
                self?.updateActiveAnchor()
            }
        }

        func recomputeAnchorPositions() {
            guard let textView, let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                anchorYPositions = []
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let inset = textView.textContainerInset.height

            anchorYPositions = viewModel.displayableAnchors.map { anchor in
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: anchor.range.location, length: 1),
                    actualCharacterRange: nil
                )
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                return rect.minY + inset
            }
        }

        @objc func boundsDidChange(_ notification: Notification) {
            updateActiveAnchor()
        }

        private func updateActiveAnchor() {
            if let suppress = suppressScrollSpyUntil, Date() < suppress {
                return
            }
            suppressScrollSpyUntil = nil

            guard let scrollView else { return }
            let visibleTop = scrollView.contentView.bounds.minY
            let newIndex = TableOfContentsViewModel.computeActiveAnchorIndex(
                visibleTop: visibleTop,
                anchorYPositions: anchorYPositions
            )
            if newIndex != viewModel.activeAnchorIndex {
                viewModel.activeAnchorIndex = newIndex
            }
        }

        private func wireScrollHandler() {
            viewModel.scrollHandler = { [weak self] index in
                self?.scrollToAnchor(at: index)
            }
        }

        private func scrollToAnchor(at index: Int) {
            guard let scrollView,
                  anchorYPositions.indices.contains(index) else { return }

            let targetY = max(0, anchorYPositions[index] - 8)
            suppressScrollSpyUntil = Date().addingTimeInterval(0.2)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
```

- [ ] **Step 2: Verify all tests still pass**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```
Expected: PASS. The coordinator uses the pure activation function from Task 6, which is already covered by tests.

- [ ] **Step 3: Build the host app**

```bash
xcodebuild build -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookApp -destination 'platform=macOS' -configuration Debug
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/MarkdownTextView.swift
git commit -m "$(cat <<'EOF'
feat: drive TOC scroll-spy and click-to-scroll from MarkdownTextView coordinator

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: End-to-end verification and manual fixture checks

**Files:**
- None (verification only).

- [ ] **Step 1: Run the full test matrix**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```
Expected: every suite PASS.

- [ ] **Step 2: Build and register the extension via dev-preview**

```bash
./Scripts/dev-preview.sh
```
Wait for the script to complete. It builds, registers, and clears Quick Look caches.

- [ ] **Step 3: Manual fixture checks**

In Finder, select each fixture and press Space to preview:

- `Fixtures/Sample.md` — has 6 headings (h1 + 5 h2). **Expected:** sidebar visible on the left, all six entries present, "Markdown Quick Look" highlighted at top of scroll. Scroll down: highlight follows. Click "Image Test": scrolls to it.
- `Fixtures/Showcase.md` — 5 headings. **Expected:** sidebar visible.
- `Fixtures/FrontMatter.md` — check whether it has ≥2 displayable headings. If not, **expected:** no sidebar chrome.
- A new throwaway markdown file with only `# Just one`. **Expected:** no sidebar chrome.

Verify the chevron toggle:
- Click the chevron in the sidebar header. Sidebar collapses to the 28pt strip.
- Quit Quick Look (Esc), open another markdown file with headings. **Expected:** the strip is shown, not the full sidebar (collapsed state persisted).
- Click the strip's chevron. Sidebar expands.
- Close, reopen another file. **Expected:** sidebar is shown (expanded state persisted).

Verify long heading text truncates with tooltip: create a file containing `# A very long heading that would not fit in 220 points of horizontal space` and confirm ellipsis + tooltip on hover.

- [ ] **Step 4: If any manual check fails, file the issue precisely**

If a check fails, do not paper over it with a follow-up task. Identify the exact misbehavior, decide whether the fix belongs in this plan (loop back to the responsible task) or in a follow-up issue, and proceed accordingly. Record the result either way.

- [ ] **Step 5: Final summary commit (only if any verification-driven changes were needed)**

If Steps 3–4 surfaced no issues, no commit is needed — the feature is complete. If small fixes were made, commit them with a `fix:` prefix referencing the manual check that found them. Example:

```bash
git add <files>
git commit -m "$(cat <<'EOF'
fix: <specific issue found during manual TOC verification>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Report**

Summarize the verification results in the conversation: list each fixture/scenario tested and PASS/FAIL.

---

## Self-review notes

- Spec coverage: every product decision in the spec maps to a task — Anchor data (Tasks 1–3), filter to h1–h3 (Task 4), persistence (Task 5), activation rule (Task 6), view-model wiring (Task 7), sidebar/strip views (Task 8), HStack layout (Task 9), scroll-spy + click-to-scroll (Task 10), end-to-end verification including the long-heading and persistence cases (Task 11).
- Type consistency check: `TableOfContentsViewModel` evolves across Tasks 4–6 then is consumed unchanged by Tasks 7–10. Method names (`setAnchors`, `requestScroll`, `computeActiveAnchorIndex`) and property names (`displayableAnchors`, `activeAnchorIndex`, `collapsed`, `shouldShowSidebar`, `shouldShowExpandStrip`) match across tasks. `HeadingAnchor`'s `(level, text, range)` shape is identical from Task 1 onward.
- Out-of-scope items from the spec (settings panel toggle, configurable depth, drag-resize, thumbnail TOC) are not in any task and stay out.
