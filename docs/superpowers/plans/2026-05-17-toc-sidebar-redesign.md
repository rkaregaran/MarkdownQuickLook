# TOC Sidebar Native Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the TOC sidebar feel native to macOS (Finder/Mail-style full-row accent selection, vibrancy background, pill rows), and remove the manual collapse/expand toggle entirely.

**Architecture:** Three tightly-related edits. Task 1 strips out the toggle surface (kills `SidebarExpandStrip`, `tocViewModel.collapsed`, its persistence, and the matching `PreviewRootView` branch). Task 2 restyles `TableOfContentsSidebar` rows to the Finder pill pattern and removes the "CONTENTS" header. Task 3 is end-to-end manual verification.

**Tech Stack:** SwiftUI, AppKit (`NSScrollView`/`NSTextView` via `NSViewRepresentable`), XcodeGen, XCTest, macOS 14.0+.

**Spec:** `docs/superpowers/specs/2026-05-17-toc-sidebar-redesign-design.md`

---

## Conventions for every task

- Run `xcodegen generate` only if `project.yml` changes (it doesn't in this plan).
- Run targeted test suite via:
  ```bash
  xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme <Scheme> -destination 'platform=macOS'
  ```
- Commit plainly with the Co-Authored-By footer used by existing commits in this branch. **Do not** add `--no-gpg-sign`, `-c commit.gpgsign=false`, or `--no-verify`. If 1Password SSH-agent rejects, retry once; if it persists, surface the error rather than working around.
- Touch only files listed in the task.
- Each task ends green (all three test schemes pass) and committed.

---

## Task 1: Remove manual collapse/expand and its persistence

This task eliminates the toggle entirely: drops the `collapsed` flag and `UserDefaults` persistence from the view model, deletes `SidebarExpandStrip`, and simplifies the `PreviewRootView` HStack branch. The visual redesign of the sidebar's rows comes in Task 2.

**Files:**
- Modify: `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift`
- Modify: `MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift`
- Modify: `MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift` (delete `SidebarExpandStrip` only — keep rest unchanged for Task 2)
- Modify: `MarkdownQuickLookPreviewExtension/PreviewRootView.swift`

- [ ] **Step 1: Simplify `TableOfContentsViewModel.swift`**

Replace the entire contents of `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift` with:

```swift
import Combine
import Foundation
import MarkdownRendering

@MainActor
final class TableOfContentsViewModel: ObservableObject {
    @Published private(set) var displayableAnchors: [HeadingAnchor] = []
    @Published var activeAnchorIndex: Int?

    var scrollHandler: ((Int) -> Void)?

    var shouldShowSidebar: Bool { displayableAnchors.count >= 2 }

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
}
```

Removed compared to the previous version: `static let collapsedDefaultsKey`, `@Published var collapsed: Bool` (with its `didSet`), `private let defaults: UserDefaults`, both initializers' `UserDefaults` plumbing, `hasEnoughHeadings`, `shouldShowExpandStrip`. `shouldShowSidebar` now derives directly from `displayableAnchors.count`.

- [ ] **Step 2: Update `TableOfContentsViewModelTests.swift`**

Replace the entire contents of `MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift` with:

```swift
import MarkdownRendering
import XCTest

@MainActor
final class TableOfContentsViewModelTests: XCTestCase {
    func testDisplayableAnchorsKeepsLevelsOneThroughThree() {
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

    func testShouldShowSidebarForEmptyHeadings() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([])
        XCTAssertFalse(viewModel.shouldShowSidebar)
    }

    func testShouldShowSidebarForSingleHeading() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1)])
        XCTAssertFalse(viewModel.shouldShowSidebar)
    }

    func testShouldShowSidebarFlipsAtTwoDisplayableHeadings() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])
        XCTAssertTrue(viewModel.shouldShowSidebar)
    }

    func testShouldShowSidebarIgnoresLevelsBelowThree() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 4), anchor(level: 5), anchor(level: 6)])
        XCTAssertFalse(viewModel.shouldShowSidebar)
    }

    func testActiveAnchorIndexClampsWhenAnchorsShrink() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2), anchor(level: 3)])
        viewModel.activeAnchorIndex = 2

        viewModel.setAnchors([anchor(level: 1)])

        XCTAssertNil(viewModel.activeAnchorIndex)
    }

    func testSetAnchorsClearsActiveIndexAtEqualBoundary() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])
        viewModel.activeAnchorIndex = 1

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

    func testRequestScrollWithNilHandlerStillUpdatesActiveIndex() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])

        XCTAssertNil(viewModel.scrollHandler)
        viewModel.requestScroll(to: 1)

        XCTAssertEqual(viewModel.activeAnchorIndex, 1)
    }

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

    func testActiveAnchorIndexExactBoundarySelectsThatAnchor() {
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 76,
            anchorYPositions: [50, 100, 200]
        )
        XCTAssertEqual(result, 1)
    }

    func testActiveAnchorIndexOnePastBoundaryFallsBackToPrevious() {
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 76,
            anchorYPositions: [50, 101, 200]
        )
        XCTAssertEqual(result, 0)
    }

    private func anchor(level: Int, location: Int = 0) -> HeadingAnchor {
        HeadingAnchor(level: level, text: "H\(level)", range: NSRange(location: location, length: 0))
    }
}
```

Removed: `testVisibilityWhenExpandedAndCollapsed`, `testCollapsedFlagPersistsThroughInjectedDefaults`, `testCollapsedFlagDefaultsToFalseInFreshDefaults`, `testCollapsedNoOpAssignmentDoesNotOverwriteDefaults`. Renamed visibility tests to match the simpler `shouldShowSidebar`-only surface. Active-anchor tests are unchanged.

- [ ] **Step 3: Delete `SidebarExpandStrip` from `TableOfContentsSidebar.swift`**

Open `MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift`. Find the `struct SidebarExpandStrip: View { ... }` declaration at the bottom of the file (it follows the `private struct TableOfContentsRow`). Delete the entire struct including its body. The file now ends with the closing brace of `TableOfContentsRow`.

Do not change `TableOfContentsSidebar` or `TableOfContentsRow` in this step — the visual restyle is Task 2.

- [ ] **Step 4: Simplify `PreviewRootView.swift`**

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
        HStack(spacing: 0) {
            if tocViewModel.shouldShowSidebar {
                TableOfContentsSidebar(viewModel: tocViewModel)
                    .frame(width: 220)
                    .background(.regularMaterial)
                    .transition(.move(edge: .leading))
                Divider()
            }

            contentColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: tocViewModel.shouldShowSidebar)
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

Removed: the `else if tocViewModel.shouldShowExpandStrip` branch and the second `.animation(...)` modifier watching `shouldShowExpandStrip`. Added: `.background(.regularMaterial)` on the sidebar's frame (vibrancy).

- [ ] **Step 5: Run all test schemes**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

Expected: PASS for all three. The preview-extension suite should report 17 tests (10 view-model tests + 7 pre-existing PreviewExtension tests = down from 37 because four collapsed-related tests were removed; the 7 pre-existing tests in other files are unchanged).

Note: the implementer should double-check the exact count by reading the actual output rather than relying on the number here; the assertion is "no failures, no regressions in tests that weren't intentionally removed".

- [ ] **Step 6: Build the host app**

```bash
xcodebuild build -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookApp -destination 'platform=macOS' -configuration Debug
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift MarkdownQuickLookPreviewExtension/PreviewRootView.swift
git commit -m "$(cat <<'EOF'
refactor: remove TOC sidebar collapse/expand toggle and its persistence

Drops the chevron, the expand strip, the collapsed flag on
TableOfContentsViewModel, and the UserDefaults persistence the flag
needed. The sidebar is now purely auto-shown when the document has
two or more displayable headings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Restyle sidebar rows in Finder pill style

This task replaces the visual treatment in `TableOfContentsSidebar`: no header, pill-shaped rows with horizontal margin, full-row accent color when active, vibrancy-aware hover.

**Files:**
- Modify: `MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift`

- [ ] **Step 1: Replace `TableOfContentsSidebar.swift`**

Replace the entire contents of `MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift` with:

```swift
import MarkdownRendering
import SwiftUI

struct TableOfContentsSidebar: View {
    @ObservedObject var viewModel: TableOfContentsViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(viewModel.displayableAnchors.enumerated()), id: \.offset) { index, anchor in
                    TableOfContentsRow(
                        anchor: anchor,
                        isActive: viewModel.activeAnchorIndex == index
                    ) {
                        viewModel.requestScroll(to: index)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct TableOfContentsRow: View {
    let anchor: HeadingAnchor
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    private let displayText: AttributedString
    private let tooltipText: String

    init(anchor: HeadingAnchor, isActive: Bool, action: @escaping () -> Void) {
        self.anchor = anchor
        self.isActive = isActive
        self.action = action
        let computed = Self.computeDisplayText(for: anchor.text)
        self.displayText = computed.display
        self.tooltipText = computed.tooltip
    }

    var body: some View {
        Button(action: action) {
            Text(displayText)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(textColor)
                .padding(.leading, indent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(backgroundFill)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .help(tooltipText)
        .onHover { isHovering = $0 }
    }

    private var indent: CGFloat {
        CGFloat(max(anchor.level - 1, 0)) * 12
    }

    private var textColor: Color {
        if isActive { return .white }
        return .secondary
    }

    private var backgroundFill: Color {
        if isActive { return Color.accentColor }
        if isHovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private static func computeDisplayText(for raw: String) -> (display: AttributedString, tooltip: String) {
        guard var parsed = try? AttributedString(markdown: raw) else {
            return (AttributedString(raw), raw)
        }
        parsed.link = nil
        return (parsed, String(parsed.characters))
    }
}
```

Compared to the previous file:
- The `header` computed property is gone (no "Contents" label, no chevron button).
- The `Divider()` between header and list is gone.
- The 3pt accent rectangle is gone — the active state is now the full-row fill.
- The row's outer `Button` body is restructured into a single `Text` with padding, background, and clip-shape modifiers (no inner HStack for the rectangle).
- The accessibility label modifiers on the chevron buttons are gone (the buttons are gone).

Behavior preserved:
- Inline-markdown rendering via `AttributedString(markdown:)` with `link` stripped.
- Tooltip via `.help(tooltipText)`.
- Computed-once `displayText` and `tooltipText` in `init` (no per-body re-parsing).
- Indent: `(level - 1) * 12`.

- [ ] **Step 2: Build the host app**

```bash
xcodebuild build -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookApp -destination 'platform=macOS' -configuration Debug
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run all test schemes**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

Expected: PASS for all three. No test counts changed since Task 1 — the visual restyle has no test surface.

- [ ] **Step 4: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift
git commit -m "$(cat <<'EOF'
feat: restyle TOC sidebar rows in Finder pill style

Drops the 'CONTENTS' header label. Rows now render as Finder-style
pills: 6pt horizontal margin, 5pt corner radius, 5pt/12pt padding.
Active rows fill with the system accent color and use white semibold
text — matching Finder, Mail, and Notes selection treatment. Inactive
rows use secondary foreground; hover adds a faint primary-on-5%
background.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: End-to-end verification

**Files:**
- None (verification only).

- [ ] **Step 1: Run the full test matrix**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

Expected: PASS for all three suites.

- [ ] **Step 2: Build and register the extension via dev-preview**

```bash
./Scripts/dev-preview.sh
```

The script builds, registers the extension at `.derivedData/Build/Products/Debug/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex`, and resets `quicklookd`. Note: on this developer's machine, an older Xcode-built copy of the extension may already be registered at `~/Library/Developer/Xcode/DerivedData/MarkdownQuickLook-*/Build/Products/Debug/...`. If `pluginkit -m -i com.rzkr.MarkdownQuickLook.app.preview -vvv | head -2` after running the script shows the `~/Library/.../DerivedData` path rather than the `.derivedData/` path, force the swap:

```bash
DEV="/Users/rzkr/Documents/Code/MarkdownQuickLook/.derivedData/Build/Products/Debug/MarkdownQuickLook.app/Contents/PlugIns/MarkdownQuickLookPreviewExtension.appex"
STALE_DIRS=$(/usr/bin/find /Users/rzkr/Library/Developer/Xcode/DerivedData -type d -name 'MarkdownQuickLookPreviewExtension.appex' 2>/dev/null)
for STALE in $STALE_DIRS; do
    pluginkit -r "$STALE"
done
pluginkit -a "$DEV"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f /Users/rzkr/Documents/Code/MarkdownQuickLook/.derivedData/Build/Products/Debug/MarkdownQuickLook.app
qlmanage -r
qlmanage -r cache
```

Then verify the active path:

```bash
pluginkit -m -i com.rzkr.MarkdownQuickLook.app.preview -vvv | head -2
```

It should point to `/Users/rzkr/Documents/Code/MarkdownQuickLook/.derivedData/...`.

- [ ] **Step 3: Manual fixture checks**

Open each fixture via `qlmanage -p <path>` in the background, eyeball the sidebar, then close with Esc:

- `Fixtures/Sample.md` — has 6 displayable headings. **Expected:** sidebar shows on left with vibrancy background. No "CONTENTS" label, no chevron. Rows render as pills with 6pt horizontal margin from sidebar edge. First row ("Markdown Quick Look") is highlighted with full system-accent-color fill and white semibold text. Scrolling the body updates the highlighted row.
- `Fixtures/Showcase.md` — same expectations, 5 displayable headings.
- A file with 0 or 1 headings (any short markdown file you can create) — **Expected:** no sidebar at all; content fills the whole preview.
- Click any row in `Sample.md` — body scrolls so the heading is in view. The clicked row's highlight stays until you scroll.
- Hover over an inactive row — faint gray fill appears, fades when you move the cursor away.
- Hover over the active row — the row stays accent-tinted, hover gray does NOT override.

- [ ] **Step 4: Report**

In conversation, summarize: each fixture/scenario tested, PASS/FAIL, and any visual nits to address in a follow-up. If a manual check fails, do not paper over — loop back to the responsible task or surface the issue.

---

## Self-review notes

- Spec coverage: every product decision in the spec maps to a task. Visibility simplification (Task 1), `SidebarExpandStrip` removal (Task 1), `collapsed`/persistence removal (Task 1), `PreviewRootView` simplification (Task 1), pill-row redesign (Task 2), header removal (Task 2), `.regularMaterial` background (Task 1, applied on sidebar's `.frame`), full-accent active state (Task 2), end-to-end verification (Task 3). The "Out of scope" items (suiteName access, `tableOfContentsCollapsed` UserDefaults orphan key migration) are correctly absent.
- Type consistency: `TableOfContentsViewModel`'s API after Task 1 is the canonical surface used through the rest of the plan and in Task 3's manual checks. `displayableAnchors`, `activeAnchorIndex`, `shouldShowSidebar`, `setAnchors`, `requestScroll`, `computeActiveAnchorIndex`, `activationOffset` all match between view model code and tests.
- Compile order: Task 1 atomically removes the strip type, the view-model surface that references it, the tests that test it, and the `PreviewRootView` branch that uses it. Nothing dangles between tasks.
- Animation: Task 1's `PreviewRootView` keeps a single `.animation(.easeInOut(duration: 0.18), value: tocViewModel.shouldShowSidebar)` modifier so the sidebar still slides in/out via the `.move(edge: .leading)` transition.
- File-size discipline: Task 2's `TableOfContentsSidebar.swift` is ~70 lines, well within scope.
