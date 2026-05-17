# TOC Sidebar Native Redesign — Design Spec

Date: 2026-05-17

## Goal

Reshape the existing table-of-contents sidebar to feel native to macOS — Finder/Xcode/Mail conventions — and simplify the surface area by removing manual collapse/expand. After this change the sidebar is shown when the document has two or more displayable (h1–h3) headings and is otherwise absent.

## Product decisions

| Decision | Choice |
|----------|--------|
| Visibility | Auto-show when ≥2 displayable headings. Otherwise no sidebar at all. |
| Manual toggle | **Removed.** No chevron, no expand strip, no settings toggle. |
| Position & width | Left, 220pt (unchanged) |
| Background | SwiftUI `.regularMaterial` (vibrancy / Finder-sidebar tone) |
| Header label | **Removed** ("CONTENTS" label gone — rows start near the top) |
| Row style | Finder "pill" — 5pt corner-radius, 6pt horizontal margin, 5pt/12pt vertical/horizontal padding |
| Hover state | Faint gray fill (`Color.primary.opacity(0.05)`) |
| Active state | **Full accent tint.** Row fills with `Color.accentColor`, text turns white, weight `.semibold`. Matches Finder/Mail/Notes selection treatment. |
| Inactive text | `.secondary` foreground at 12pt regular |
| Indent | 12pt per level (`(level - 1) * 12`) as leading padding inside the row |
| Scroll-spy | Unchanged behavior — active row tracks the heading the reader is currently viewing |
| Click-to-scroll | Unchanged — calls into existing `MarkdownTextView.Coordinator` plumbing |

## What this removes

- `TableOfContentsViewModel.collapsed` (and its `UserDefaults` persistence)
- `TableOfContentsViewModel.shouldShowExpandStrip`
- `TableOfContentsViewModel.collapsedDefaultsKey`
- `SidebarExpandStrip` (entire SwiftUI type)
- The header row in `TableOfContentsSidebar` (the "Contents" label + chevron-left button)
- The `else if shouldShowExpandStrip` branch in `PreviewRootView`
- The persistence tests in `TableOfContentsViewModelTests` (collapsed round-trip, no-op idempotency)
- The `MarkdownSettingsStore.suiteName` access widening from the original Task 5 stays — it's a benign public constant and other code could grow to use it; YAGNI says revert if/when proven unused, but for this spec it's out of scope.

## What this keeps

- All renderer-side anchor extraction (Tasks 1–3)
- View-model filtering, active-anchor tracking, scroll handler wiring (Tasks 4, 6)
- `MarkdownTextView.Coordinator` scroll observation and click-to-scroll (Task 10)
- Sidebar HStack composition with `Divider()` and slide transition (Task 9)

## Visual specification

### Sidebar container

```swift
TableOfContentsSidebar(viewModel: tocViewModel)
    .frame(width: 220)
    .background(.regularMaterial)
    .transition(.move(edge: .leading))
```

`.regularMaterial` gives the subtle Finder-sidebar vibrancy. No top header — rows start at ~6pt from the top of the sidebar's content area, with no label above them.

### Row layout (inside `TableOfContentsRow`)

```
┌────────────────────────────────────────┐ ← row, 6pt left/right margin
│       Heading text                     │ ← active: blue fill, white semibold
└────────────────────────────────────────┘
  ↑ leading inset = 12 + (level - 1) * 12
```

- Outer container: 6pt horizontal margin from sidebar edges.
- Outer container fill: 5pt corner radius. Inactive = `.clear`. Hover = `Color.primary.opacity(0.05)`. Active = `Color.accentColor`.
- Inner padding: 5pt vertical, 12pt horizontal.
- Indent (extra left padding inside the row): `(level - 1) * 12`. So h1 entries have 12pt left padding, h2 have 24pt, h3 have 36pt.
- Text: system font, size 12.
  - Inactive: `.secondary` foreground, weight `.regular`.
  - Active: `.white` foreground, weight `.semibold`.
  - Inline markdown rendered via cached `AttributedString(markdown:)` with `link` attribute stripped (already implemented).
- Truncation: single line, `.tail` ellipsis. Tooltip via `.help(tooltipText)` (cached plain-text form).
- Hover: `@State private var isHovering`. The row's outer fill switches between `.clear` and `Color.primary.opacity(0.05)` on hover, unless active.

### Active vs. hover precedence

If a row is both hovered and active, **active wins**. The fill is the accent color, not the hover gray. This matches Finder — hover over the currently-selected row and it stays accent-blue.

### Row spacing

The sidebar uses a `LazyVStack(alignment: .leading, spacing: 2)` inside the `ScrollView`. 2pt between rows gives the pill style visual breathing room. The 6pt horizontal margin on each row prevents pills from touching the sidebar edges.

### Top/bottom inset of the row list

`LazyVStack` has `.padding(.vertical, 6)` so the first row isn't flush against the top of the sidebar.

## State machine

```
displayable        = anchors.filter { $0.level <= 3 }
shouldShowSidebar  = displayable.count >= 2
```

That's it. No `collapsed` flag, no `shouldShowExpandStrip`.

## Code changes

### `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift`

Remove:
- `static let collapsedDefaultsKey`
- `@Published var collapsed: Bool { didSet { … } }`
- `private let defaults: UserDefaults`
- `convenience init()` and `init(defaults:)` — replace with parameterless `init()`
- `shouldShowExpandStrip` computed property

Simplify:
- `shouldShowSidebar` becomes `displayableAnchors.count >= 2` directly (the intermediate `hasEnoughHeadings` was only useful when there were two visibility computations to share it; drop it)
- `import Combine` stays (required for `ObservableObject` / `@Published`); `import Foundation` and `import MarkdownRendering` stay

Final shape:

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

### `MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift`

Remove:
- The whole `header` computed property
- The `Divider()` after the header (no header → no divider)
- `SidebarExpandStrip` type (entire struct)

Replace the existing `TableOfContentsRow` body with the pill style: outer fill picks `.clear` / hover / active, inner padding stays, the 3pt accent rectangle is removed.

Final shape:

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

### `MarkdownQuickLookPreviewExtension/PreviewRootView.swift`

Remove the `else if tocViewModel.shouldShowExpandStrip` branch. Add the `.regularMaterial` background on the sidebar.

```swift
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
```

The second `.animation(...)` modifier (for `shouldShowExpandStrip`) is removed. The strip's `else if` branch is removed.

### `MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift`

Remove:
- `testCollapsedFlagPersistsThroughInjectedDefaults`
- `testCollapsedFlagDefaultsToFalseInFreshDefaults`
- `testCollapsedNoOpAssignmentDoesNotOverwriteDefaults`

Update:
- `testVisibilityWhenExpandedAndCollapsed` — rename to `testVisibilityFlipsWithAnchorCount` and test only that `shouldShowSidebar` flips with the heading count.
- Any test that uses `init(defaults:)` switches to the parameterless `init()`.
- `testVisibilityForEmptyHeadings` and `testVisibilityForSingleHeading` no longer assert on `shouldShowExpandStrip` — just `shouldShowSidebar`.
- `testVisibilityIgnoresLevelsBelowThree` same simplification.

The activation-rule tests (`testActiveAnchorIndex*`) stay unchanged — they don't touch persistence or visibility.

## Edge cases

| Case | Behavior |
|------|----------|
| 0 displayable headings | No sidebar chrome at all |
| 1 displayable heading | No sidebar chrome at all |
| ≥2 displayable headings | Sidebar visible on left, 220pt wide, with vibrancy bg |
| Heading with inline markdown like `**bold**` | Row renders parsed `AttributedString`, link attribute stripped, falls back to raw text on parse failure (unchanged behavior) |
| Active row changes during scroll | Color tweens smoothly courtesy of SwiftUI's default `.animation` on `Color.accentColor` value changes — should feel fluid, not jumpy |
| Hover an active row | Active wins; row stays accent-tinted |
| Window narrower than sidebar + minimum content | Content column gets squeezed; v1 doesn't auto-hide sidebar at narrow widths (unchanged) |

## Out of scope

- Reverting `MarkdownSettingsStore.suiteName` to internal (orphan public constant; safe to leave for now)
- Migrating away from the `tableOfContentsCollapsed` UserDefaults key (orphan key in user defaults — harmless dust; no migration code)
- Re-introducing a toggle later — if we ever need it back, it's a fresh design (most likely via the host app's settings panel rather than a chevron)
- Touching `MarkdownTextView.Coordinator` or scroll-spy logic
- Touching renderer-side anchor extraction
