# Batch 3: Thumbnails & Polish — Design Spec

## Goal

Add Finder thumbnail generation for `.md` files and improve rendering of special code blocks (mermaid, math) with labeled headers.

## Feature 1: Finder Thumbnails

**What it does:** When Finder shows `.md` files in icon, column, or gallery view, macOS shows a generic file icon. With a thumbnail extension, we generate a mini-preview of the markdown content as the file's thumbnail — making `.md` files visually distinguishable at a glance.

**Architecture:** A new `QLThumbnailProvider` app extension target embedded in the host app, alongside the existing preview extension. It reuses the `MarkdownRendering` framework to parse and render the document, then draws the attributed string into a bitmap image.

**New target:** `MarkdownQuickLookThumbnailExtension`
- Type: `app-extension`
- Extension point: `com.apple.quicklook.thumbnail`
- Principal class: `ThumbnailProvider` (subclass of `QLThumbnailProvider`)
- Bundle ID: `com.rzkr.MarkdownQuickLook.app.thumbnail`
- Depends on: `MarkdownRendering`
- Sandboxed with `files.user-selected.read-only`

**Rendering approach:**
1. Parse the markdown file using `MarkdownDocumentRenderer.prepareDocument(fileAt:)`
2. Render to `NSAttributedString` using `MarkdownDocumentRenderer.render(document:)`
3. Create an `NSImage` by drawing the attributed string into a bitmap context at the requested thumbnail size
4. Return the image via the `QLThumbnailReply`

The thumbnail only shows the first portion of the document that fits in the requested size — no scrolling needed.

**Supported content types:** `net.daringfireball.markdown` (same as preview extension)

## Feature 2: Labeled Special Code Blocks

**What it does:** Code blocks with language hints like `mermaid`, `math`, `latex`, or `diagram` render with a descriptive header label instead of trying to execute them. This tells the user what the block represents.

**Example:** A ` ```mermaid` block renders as:

```
┌─ Mermaid Diagram ──────────────┐
│ graph TD                       │
│   A --> B                      │
│   B --> C                      │
└────────────────────────────────┘
```

**Implementation:** In `appendCodeBlock`, check the language hint. If it matches a known diagram/math language, prepend a styled label line before the code content. The label uses bold monospaced font in a subtle color.

**Recognized labels:**
| Language hint | Label |
|---|---|
| `mermaid` | Mermaid Diagram |
| `math`, `latex`, `tex` | Math Expression |
| `diagram` | Diagram |

No rendering changes beyond the label — the code content renders as normal syntax-highlighted code.

## File Changes

| File | Change |
|---|---|
| `project.yml` | Add `MarkdownQuickLookThumbnailExtension` target |
| `MarkdownQuickLookThumbnailExtension/ThumbnailProvider.swift` | New: QLThumbnailProvider implementation |
| `MarkdownQuickLookThumbnailExtension/Info.plist` | New: extension metadata |
| `MarkdownQuickLookThumbnailExtension/MarkdownQuickLookThumbnailExtension.entitlements` | New: sandbox entitlements |
| `MarkdownDocumentRenderer.swift` | Add labeled header for special code blocks |
| `MarkdownDocumentRendererTests.swift` | Tests for labeled code blocks |

## Out of Scope

- Actual Mermaid/LaTeX rendering (requires JavaScript runtime)
- Thumbnail caching (macOS handles this)
- Custom thumbnail sizes (QLThumbnailProvider receives the requested size)
