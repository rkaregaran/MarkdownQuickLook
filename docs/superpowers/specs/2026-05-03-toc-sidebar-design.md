# Table of Contents Sidebar — Design Spec

Date: 2026-05-03

## Goal

Add a left-side table of contents sidebar to the Markdown Quick Look preview. The sidebar lists the document's headings (h1–h3), highlights the heading the reader is currently viewing as they scroll, and lets the reader click an entry to jump to that heading. The sidebar is auto-shown when the document has two or more displayable headings and can be collapsed by the user with a chevron; the collapsed/expanded preference persists across previews.

## Product decisions

| Decision | Choice |
|----------|--------|
| Visibility | Auto-show when ≥2 displayable (h1–h3) headings, with user toggle |
| Position & width | Left, fixed 220pt |
| Scroll-spy | Yes — active heading highlights as user scrolls |
| Heading depth | Show h1–h3 only |
| Toggle UI | Chevron in sidebar header collapses; thin 28pt strip with reverse chevron re-expands |
| Long heading text | Single line, truncate with ellipsis, native tooltip on hover |
| Persistence | Single bool key in App Group `UserDefaults` |

## Architecture

The feature touches both the rendering framework and the preview extension.

```
MarkdownRendering (framework)
└── Renderer emits HeadingAnchor list on MarkdownRenderPayload
        │ (text, level, NSRange into attributedContent)
        ▼
MarkdownQuickLookPreviewExtension
├── PreviewViewController owns a TableOfContentsViewModel
├── PreviewRootView lays out HStack { sidebar | divider | content }
├── TableOfContentsSidebar renders the heading list
└── MarkdownTextView.Coordinator
       ├── observes NSClipView bounds changes → updates activeAnchorIndex
       └── handles scrollRequest → scrolls NSTextView to anchor's y
```

Single source of truth for heading data: the renderer. The preview extension never re-walks the markdown — it consumes `MarkdownRenderPayload.tableOfContents` and maps anchor `NSRange`s through the text view's layout manager.

## Data model

### `HeadingAnchor` (new public type in `MarkdownRendering`)

```swift
public struct HeadingAnchor: Equatable, Sendable {
    public let level: Int        // 1...6, all levels emitted
    public let text: String      // raw markdown text after the leading #'s
    public let range: NSRange    // location into MarkdownRenderPayload.attributedContent
}
```

The renderer emits anchors for **all six levels**. The h1–h3 cap is applied at display time in the sidebar. This keeps the rendering layer purely structural and avoids touching the renderer if we ever change the cap.

### `MarkdownRenderPayload` extension

```swift
public struct MarkdownRenderPayload {
    public let title: String
    public let attributedContent: NSAttributedString
    public let tableOfContents: [HeadingAnchor]   // [] when no headings
}
```

Both `render(document:)` and `render(document:shouldContinue:)` capture `formatted.length` immediately before each `.heading` block is appended, then build `HeadingAnchor(level:, text:, range: NSRange(location: capturedLength, length: 0))`.

The range has length 0 because the anchor is a *position*, not a span; the y-position lookup uses `boundingRect(forCharacterRange:)` for a single character starting at that location, which is sufficient.

### Persistence

Sidebar collapsed state is a UI preference, not a render parameter. It lives in the existing App Group `UserDefaults` under `group.com.rzkr.MarkdownQuickLook`, with key `tableOfContentsCollapsed: Bool` (default `false`). It does **not** go on `MarkdownRenderSettings` — that struct is reserved for parameters that affect rendering output.

## UI

### Layout

```swift
HStack(spacing: 0) {
    if shouldShowSidebar {
        TableOfContentsSidebar(viewModel:)
            .frame(width: 220)
        Divider()
    } else if shouldShowExpandStrip {
        SidebarExpandStrip(action:)
            .frame(width: 28)
        Divider()
    }
    contentColumn   // existing title + MarkdownTextView
}
.animation(.easeInOut(duration: 0.18), value: shouldShowSidebar)
```

### Visibility state machine

Computed each render from anchors + collapsed flag:

```
displayable           = anchors.filter { $0.level <= 3 }
hasEnoughHeadings     = displayable.count >= 2

shouldShowSidebar     = hasEnoughHeadings && !collapsed
shouldShowExpandStrip = hasEnoughHeadings && collapsed
no chrome at all       = !hasEnoughHeadings
```

`hasEnoughHeadings` always wins: a document with 0–1 displayable headings shows zero sidebar chrome regardless of the collapsed flag, so users never see an empty sidebar.

### Sidebar contents

Top to bottom:

1. **Header row** — `"Contents"` label (small caps / secondary color) + chevron-left button on the right edge. Tapping the chevron sets `collapsed = true`.
2. **`ScrollView` of `LazyVStack`** — one `TableOfContentsRow` per displayable anchor.

`TableOfContentsRow`:
- Indent: leading padding `(level - 1) * 12pt`
- Text rendered via `Text(AttributedString(markdown:) ?? text)` so inline `**bold**` / `*italic*` / `[link]()` formatting in headings renders correctly; falls back to raw string on parse failure
- `.lineLimit(1)` + `.truncationMode(.tail)`
- `.help(text)` for native tooltip showing full heading
- `.onHover` adds a faint background fill
- Active row (matches `viewModel.activeAnchorIndex`): 3pt left accent bar in `.accentColor`, foreground `.primary` with `.bold()`; non-active rows use `.secondary` foreground
- Whole row is the click target → `viewModel.requestScroll(to: index)`

### Expand strip (collapsed state)

A 28pt-wide vertical strip with a single chevron-right button at the top. Background uses the same subtle fill as the sidebar so the strip reads as collapsed-sidebar chrome rather than orphan UI. Clicking sets `collapsed = false`.

## Scroll-spy and click-to-scroll

Both behaviors require mapping `NSRange` → vertical y-position, which only works with the live `NSLayoutManager` and `NSTextContainer` of the `NSTextView`. That logic lives inside `MarkdownTextView`'s `Coordinator`.

### `MarkdownTextView` evolution

```swift
struct MarkdownTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    @ObservedObject var tocViewModel: TableOfContentsViewModel

    func makeCoordinator() -> Coordinator
    final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        var tocViewModel: TableOfContentsViewModel?
        var anchorYPositions: [CGFloat] = []
        var suppressScrollSpyUntil: Date?

        func recomputeAnchorPositions()
        @objc func boundsDidChange(_ note: Notification)
        func scrollToAnchor(at index: Int)
    }
}
```

`TableOfContentsViewModel` is always present (never optional). When the document has no displayable headings, the view model's `anchors` array is empty: the sidebar isn't rendered, the coordinator's `recomputeAnchorPositions()` short-circuits, and `boundsDidChange` has nothing to update. This avoids `Optional<ObservedObject>` gymnastics and keeps the wiring uniform.

### Scroll observer wiring

- In `makeNSView`, after building the `NSScrollView` + `NSTextView`:
  - `scrollView.contentView.postsBoundsChangedNotifications = true`
  - `NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.boundsDidChange(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)`
- `TableOfContentsViewModel` exposes a `scrollHandler: ((Int) -> Void)?` property. The coordinator sets it in `makeNSView` to a closure that calls `scrollToAnchor(at:)`. Row taps invoke `viewModel.requestScroll(to: index)`, which calls `scrollHandler?(index)` and updates `activeAnchorIndex` immediately. No Combine import needed.
- After `updateNSView` rewrites text storage, the coordinator forces layout (`layoutManager.ensureLayout(for: textContainer)`) and recomputes `anchorYPositions` for every anchor in `tocViewModel.anchors`.

### Activation rule

```
visibleTop = scrollView.contentView.bounds.minY
threshold  = visibleTop + 24

active = largest i where anchorYPositions[i] <= threshold
       ?? 0   // before the first heading, highlight the first one
```

The +24pt threshold means a heading just scrolled into view counts as "current"; without the offset, scrolling one pixel past a heading immediately deactivates it.

### Click-to-scroll behavior

- Compute `targetY = anchorYPositions[index]`.
- `scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, targetY - 8)))` then `scrollView.reflectScrolledClipView(_:)` — places the heading 8pt below the top of the visible area.
- Set `suppressScrollSpyUntil = Date().addingTimeInterval(0.2)`. While suppressed, `boundsDidChange` does not update `activeAnchorIndex`. This keeps the clicked row highlighted instead of flickering through intermediate anchors during the scroll animation, and lets the user's click intent win.
- Set `activeAnchorIndex = index` immediately so the highlight feels responsive.

## Edge cases

| Case | Behavior |
|------|----------|
| 0 or 1 headings | No sidebar chrome at all |
| All headings are h4–h6 | Filtered out; treated as 0 headings |
| ≥2 headings, collapsed flag true | Expand strip shown |
| Heading with inline `**bold**` etc. | Row renders parsed `AttributedString`; falls back to raw text on parse failure |
| Heading text longer than sidebar width | Single-line ellipsis; full text on tooltip via `.help(_:)` |
| Window narrower than ~400pt | Sidebar still takes 220pt; content column squeezes. v1 does not auto-hide for narrow windows |
| Document re-render | Coordinator recomputes anchor positions; clamps `activeAnchorIndex` to the new range |
| Cancelled preview load | TOC view model is discarded with the controller; nothing leaks because notification observer is owned by the coordinator |

The thumbnail extension is unchanged — thumbnails are static images.

## Files

**New:**
- `MarkdownRendering/Sources/HeadingAnchor.swift`
- `MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift`
- `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift`

**Modified:**
- `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift` — collect anchors during both `render` overloads; populate `MarkdownRenderPayload.tableOfContents`
- `MarkdownQuickLookPreviewExtension/PreviewRootView.swift` — replace `VStack` with `HStack` layout; accept the TOC view model
- `MarkdownQuickLookPreviewExtension/MarkdownTextView.swift` — gain `Coordinator`, scroll observer, programmatic scroll-to-anchor
- `MarkdownQuickLookPreviewExtension/PreviewViewController.swift` — own a `TableOfContentsViewModel` instance and seed it from each `MarkdownRenderPayload`
- `project.yml` — `MarkdownRendering` and `MarkdownQuickLookPreviewExtension` use directory-glob source rules, so the new files are picked up automatically. **`MarkdownQuickLookPreviewExtensionTests` lists sources individually**, so add explicit entries:
  - `MarkdownQuickLookPreviewExtension/TableOfContentsSidebar.swift`
  - `MarkdownQuickLookPreviewExtension/TableOfContentsViewModel.swift`
  `MarkdownRenderingTests` uses a directory glob (`MarkdownRendering/Tests`) — new test files there are auto-included.

**Tests added:**
- Extend `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift` (or add a focused `MarkdownTableOfContentsTests.swift` in the same directory) — anchor extraction tests
- New `MarkdownQuickLookPreviewExtension/Tests/TableOfContentsViewModelTests.swift` — TOC view model and visibility-state-machine tests

## Testing strategy

### `MarkdownRenderingTests`

- **Empty case** — document with no headings produces empty `tableOfContents`
- **All levels** — a fixture exercising h1 through h6 produces six anchors in document order, levels 1...6
- **Range correctness** — for each anchor in the rendered output of `Fixtures/Sample.md` and `Fixtures/Showcase.md`, `attributedContent.attributedSubstring(from: NSRange(location: anchor.range.location, length: anchor.text.count))` starts with the heading's plain text (allowing for inline-markdown stripping by `AttributedString(markdown:)`). A weaker, more robust assertion: assert `attributedContent.string` contains the heading text at `anchor.range.location` after normalizing whitespace.
- **Document order** — anchor list is monotonically increasing on `range.location`

### `MarkdownQuickLookPreviewExtensionTests` (new TOC suite)

- **Visibility state machine** — table-driven test on `(headingsByLevel, collapsed) → (showSidebar, showExpandStrip)`:
  - `([], false)` → `(false, false)`
  - `([1], false)` → `(false, false)`
  - `([1, 2], false)` → `(true, false)`
  - `([1, 2], true)` → `(false, true)`
  - `([4, 5, 6], false)` → `(false, false)` (filtered out)
  - `([1, 4, 4], false)` → `(false, false)` (only one displayable)
- **Filter** — only levels 1–3 reach `displayableAnchors`
- **Persistence** — `TableOfContentsViewModel` writes `collapsed` to a stub `UserDefaults` and a fresh instance reads it back
- **Active-anchor pure function** — given an array of `anchorYPositions` and a `visibleTop`, the activation rule returns the expected index. Cases: above first anchor, exactly on a threshold, between anchors, past last anchor

### Manual verification (recorded in PR description before claiming complete)

Run `./Scripts/dev-preview.sh` against:
- `Fixtures/Sample.md` (small file)
- `Fixtures/Showcase.md` (rich, many headings)
- A doc with 0 headings
- A doc with one h1 only
- A long doc — verify scroll-spy follows scrolling smoothly
- Click each TOC entry — verify the heading lands near the top
- Toggle the chevron — verify the persisted state survives closing/reopening Quick Look on a different file

## Out of scope

- A "Show table of contents by default" toggle in the host app's settings panel — collapsed state is per-installation already
- Configurable depth (h2-only / h1–h6) — locked at h3 for v1
- Drag-resize sidebar width — fixed at 220pt
- TOC in the thumbnail extension
- Any TOC behavior in environments other than the Quick Look preview window
