# Phase 6: WKWebView Migration — Decision Spec

> **Status:** Strategic option, not committed. No implementation plan attached. This document exists so the option remains live and so a future "should we migrate?" conversation has a concrete reference instead of a vague gesture.

## TL;DR

A full migration of the preview rendering surface from `NSTextView` + hand-rolled parser to `WKWebView` + [`swift-markdown`](https://github.com/swiftlang/swift-markdown) + bundled JS (KaTeX, Mermaid, highlight.js, DOMPurify) is the path that closes the *entire* gap to pluk-inc in a single coherent rewrite. It is also the largest single change we could make, with a real risk of regressing things we currently do well (inline image attachment loading, smart-dash typography, stable QL extension behavior across macOS versions).

The recommendation: **do not migrate today.** Reconsider when one of the triggers in § "When to revisit" trips.

## What "migrating" actually means

Concrete delta from today:

| Today | After migration |
|---|---|
| `MarkdownDocumentRenderer` parses to `[MarkdownBlock]` and renders to `NSAttributedString`. | `MarkdownHTMLRenderer` parses with `swift-markdown` and renders HTML. |
| `MarkdownTextView` is `NSViewRepresentable<NSTextView>`. | `MarkdownWebView` is `NSViewRepresentable<WKWebView>`. |
| QL extension is `QLPreviewingController` (view-based). | QL extension becomes `QLPreviewProvider` (data-based), returning HTML + `QLPreviewReplyAttachment`s. |
| Inline images load via `NSImage(contentsOf:)` on text attachments. | Images rewritten to opaque keys, supplied as `QLPreviewReplyAttachment`s (mirrors pluk's `InlineLocalAssets`). |
| TOC sidebar overlays the text view with scrollspy via `NSLayoutManager` glyph rects. | TOC sidebar runs JS in the WebView; scrollspy via `IntersectionObserver`. |
| Hand-rolled syntax highlighter (~10 languages). | `highlight.js` common-languages build (~35 languages). |
| No math / Mermaid. | KaTeX + Mermaid + interactive Mermaid pan/zoom + KaTeX copy-tex all "for free." |
| `MarkdownDocumentRendererTests` validates attributed-string shape. | New test surface validates HTML output (via `EscapingHTMLFormatter`-style visitor tests). |
| Smart em/en dashes. | Lost unless we re-implement in the HTML pipeline. |
| App Group `UserDefaults` settings still readable from extension. | Unchanged. |

This is not a refactor. It is a re-platforming.

## Why this is tempting

1. **All math / diagram work disappears** as a separate workstream. KaTeX and Mermaid drop into the WebView with no rasterization gymnastics.
2. **Full GFM / CommonMark correctness** via `swift-markdown` — footnotes, reference links, alert blockquotes, table alignment, indented code blocks, raw HTML (sanitized) all come from a maintained parser instead of our hand-rolled one. Phase 1 becomes ~80% redundant.
3. **CSS theming** — light/dark, font choices, typography all become first-class instead of bespoke text attributes.
4. **Inline HTML support** with DOMPurify sanitization — no longer dropping `<kbd>`, `<mark>`, `<details>`.
5. **Selection / copy on rendered math** via KaTeX `copy-tex` extension — selecting a formula and copying yields LaTeX source.
6. **A single rendering pipeline** shared with any future host-app expansion (Phase 5).
7. **The QL preview's "marketing surface"** improves to match pluk: heading-anchor scrolling, code-block copy buttons via JS, proper task-list checkboxes.

## Why it's not "just" tempting

1. **Cost.** Conservative estimate: 6–8 person-weeks for one engineer who already knows the project, longer otherwise.
2. **Loss of existing strengths.**
   - Smart em/en dash conversion is currently a post-pass over `NSAttributedString`. In the HTML pipeline, we'd need to inject it as a remark-style transform or accept loss.
   - QL view-based extension means `NSImage(contentsOf:)` works for sibling images out of the box. Data-based requires the `InlineLocalAssets` rewrite that pluk built — non-trivial, with sandbox quirks.
   - `PreviewRequestTracker` and our cancellation logic are tested and tuned. We rebuild that with WKWebView lifecycle.
3. **WKWebView startup cost.** Pluk hit a 1s main-thread stall on first Shiki cold compile (CHANGELOG 0.0.18) and had to fall back to highlight.js. Their CHANGELOG documents painful learning curves on vendor JS performance — we'd retrace those steps. Their solution involved a "synthetic warmup doc" (CHANGELOG 0.0.18), `IntersectionObserver`-based lazy Mermaid (CHANGELOG 0.0.16), and a `md-asset://` scheme to defer 2.5MB of JS (CHANGELOG 0.0.18). We'd need to learn or copy all of it.
4. **Sandbox + WKWebView in an app-extension.** Pluk's QL uses inline-bundled JS because `QLPreviewReply` ships a single payload — no time to fetch resources. The HTML grows ~3MB just from vendor bundles. This affects QL initial-render time noticeably.
5. **Security surface.** Rendering HTML from arbitrary `.md` content (which may contain inline HTML) requires DOMPurify. Subtle bugs in sanitization = code execution. We'd inherit this as ongoing maintenance.
6. **Min macOS bump.** Pluk requires macOS 15+ in part because of `WKWebView` features they rely on. We're 14.0+ today. Migration likely raises the floor.
7. **No backward compat for our tests.** `MarkdownDocumentRendererTests`, `TableOfContentsViewModelTests`, `PreviewSizingTests` all need rewriting against the new architecture.

## Architecture (if we ever do it)

### Module layout

```
MarkdownRendering/
  Sources/
    MarkdownHTML.swift             # `swift-markdown` → HTML string
    EscapingHTMLFormatter.swift    # visitor pattern, mirrors pluk's structure
    MarkdownFrontmatter.swift      # YAML + TOML strip
    CodeFenceInfo.swift            # split language vs metadata
    Resources/
      stylesheet.css               # bundled
      Vendor/{KaTeX,Mermaid,highlight,DOMPurify}/  # bundled JS

MarkdownQuickLookPreviewExtension/
  PreviewProvider.swift            # QLPreviewProvider with QLIsDataBasedPreview = true
  InlineLocalAssets.swift          # img/src rewrite → QLPreviewReplyAttachment
  Resources/                       # nothing here; bundles live in MarkdownRendering
```

### Pipeline

1. `swift-markdown` parses Markdown into a `Document` tree.
2. `EscapingHTMLFormatter` visits each node, emitting HTML + GFM extensions (tables, alerts via `[!NOTE]` matcher, task lists, strikethrough, footnotes).
3. `MarkdownHTML.render` assembles the final HTML: `<head>` with bundled CSS + (conditionally inlined) vendor scripts based on document scan (math present? Mermaid present?), `<body>` with the article HTML inside a `<template>` element.
4. A bootstrap script (also inlined) runs DOMPurify on the template content and assigns the sanitized result to a real `<article>` element. KaTeX, Mermaid, highlight.js initialize after first paint.

For the QL extension, vendor JS is inlined (`VendorLoading.inline` in pluk parlance). For the host app, we could optionally defer via a `md-asset://` `WKURLSchemeHandler`.

### Sandbox / image handling

`InlineLocalAssets.rewriteRelativeImages(html:baseDirectory:reader:)` scans the HTML for relative `<img src="…">` paths, replaces them with opaque token URLs, and supplies the bytes via `QLPreviewReplyAttachment` map keyed by the same tokens. This is what makes images work inside the QL sandbox without `com.apple.security.network.client` or temporary-exception entitlements.

### Renderer fingerprinting

Pluk introduced a `RendererFingerprint.covers(_:)` check (CHANGELOG 0.0.18) that lets the WebView skip a full reload when only the article body changed and the (math / Mermaid / highlight) mix didn't. Worth designing in from the start — saves us multi-second reloads on consecutive `.md` previews.

## Migration sequencing (sketch — not a plan)

If we ever commit to this, the sequencing roughly:

1. **Build `MarkdownHTML.swift` alongside the existing renderer.** No removal yet. Add tests that compare output for a set of fixtures.
2. **Build the QL `PreviewProvider`** in parallel to the existing `PreviewViewController`. Land behind a build-flag or alternate target so users still get the old path.
3. **Land the host app on the new pipeline first** (lower-stakes surface). Iterate on perf there.
4. **Cut over the QL extension.** Keep the old path around as a fallback for one or two releases.
5. **Delete the hand-rolled parser** once shipping is confirmed stable.

Estimated time per stage: 2 weeks, 2 weeks, 1 week, 1 week, 2 weeks. Total: 8 weeks.

## What we keep regardless

- App Group `UserDefaults` for settings.
- The TOC sidebar UX (port the data layer; rebuild the view layer against HTML headings).
- The `qlmanage -p` review workflow.
- Existing `Fixtures/` for snapshot baselines.
- CI pipeline.

## What we lose unless we re-build

- Smart dashes — must be re-implemented as an `EscapingHTMLFormatter` post-pass.
- macOS 14.0 support — likely floored at 15.0.
- Our specific image-attachment cancellation behavior.
- Several `NSAttributedString`-shape assertions in tests; rewrite needed.

## When to revisit

Migrate if **any one** of these becomes true:

1. **Phase 4 (math/diagrams rasterization) spike fails on cold-start latency** and users are asking for math.
2. **A user-facing inline HTML request that we can't satisfy** in the text pipeline. Examples that have come up in other Markdown projects: `<details>` collapsible sections, `<kbd>` keyboard chords styled distinctly, `<mark>` highlights, custom callout boxes via HTML.
3. **We commit to expanding the host app meaningfully** (Phase 5 expansion beyond the minimal subset). Sharing the renderer with the app is worth a lot.
4. **A specific user-visible regression** in our hand-rolled parser comes up that's hard to fix without a real parser (e.g., setext headings + ATX-like edge cases, fence-info-string metadata in non-trivial form, nested list edge cases).
5. **We hit a perf ceiling in the text pipeline** — large `Fixtures/Performance/*.md` files start regressing as we add features.

## Decision-quality data we'd want before committing

If/when this becomes a real conversation, gather:

- **Current QL cold-start latency** for a typical 10KB `.md` (instrumented). Set a floor.
- **WKWebView cold-start latency** in our specific extension context (data-based provider, sandboxed). Pluk implies it's their dominant cost.
- **`swift-markdown` parse time** for our `Fixtures/Performance/large.md`. Apple says it's cmark-gfm-backed; should be fast.
- **HTML size** for a typical doc, with and without vendor bundles. Quantifies what `QLPreviewReply` ships.
- **A test render** of `Fixtures/Showcase.md` and `Fixtures/Sample.md` in the new pipeline. Compare side-by-side to current.

## Adopt `swift-markdown` without migrating?

A partial commitment: replace just the parsing layer with `swift-markdown` (it's a Swift Package — free to add) and keep `NSAttributedString` as the render target. This buys:

- Real CommonMark + GFM correctness.
- Footnote / reference-link / alert support without hand-rolling parsers.
- Mature handling of edge cases.

Without:

- Math / diagrams (still need rasterization).
- Inline HTML.
- CSS theming.

This is a tractable middle path. The implementation cost is ~1–2 weeks. The catch is we'd be writing visitor code from `Markdown.Document` → `NSAttributedString` that mirrors what `EscapingHTMLFormatter` does for HTML. Some Phase 1 work becomes redundant, some becomes the *implementation* of those visitor methods.

**Recommendation if we go this route:** treat it as Phase 1.5, after Phase 1 completes and Phase 4 fails the rasterization spike. Don't do it preemptively — we lose the optionality of a hand-rolled parser that's tuned for our specific behaviors.

## Honest assessment

If a year-from-now version of this project is competing with pluk on feature breadth, we end up migrating. Pluk's CHANGELOG shows they get to do work like "GitHub alert blockquotes" or "atomic-save reload" in days because their architecture front-loaded the hard part. Ours has to keep building parsers.

If a year-from-now version of this project is winning on Quick Look-specific polish (fast cold-open, view-based extension that works under tight sandbox, TOC sidebar inside the preview) — none of that requires WebKit. We can stay where we are.

The roadmap recommends the latter framing for now. If user signals change that, this document is the starting point for the migration conversation.
