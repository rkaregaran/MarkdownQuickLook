# Batch 2: Rendering Features — Design Spec

## Goal

Add nested lists, inline images, and YAML front matter handling to improve markdown rendering quality for real-world documents.

## Feature 1: Nested Lists

**Syntax:**
```markdown
- Top level
  - Nested bullet
    - Deeply nested
- Back to top

1. First
   1. Sub-first
   2. Sub-second
2. Second
```

**Parsing:** Currently `MarkdownListItem` holds `paragraphs: [String]` and `index: Int?`. To support nesting, add a `children: [MarkdownListItem]` field. A nested item is detected when the next line is indented (2+ spaces or tab) AND matches bullet or ordered list syntax.

The parser needs to:
1. Track indentation level of the current list
2. When a line is more indented and starts with a bullet/number, parse it as a child item
3. Recurse for deeper nesting

**Rendering:** Each nesting level increases the left indent. Use the existing `hangingIndentAttributes` but with `indent * depth` for the `firstLineHeadIndent` and `headIndent`. Nested bullets alternate: `•`, `◦`, `▪` for levels 0, 1, 2+.

## Feature 2: Images

**Syntax:** `![alt text](path/to/image.png)` or `![alt text](https://example.com/img.png)`

**Parsing:** Images at the block level (a paragraph consisting solely of an image) should render as an inline image. Images within text render as `[alt text]` placeholder since inline images in `NSAttributedString` break text flow.

Detection: a paragraph whose text matches `^!\[.*\]\(.*\)$` (the entire paragraph is a single image reference).

New `MarkdownBlock.image(alt: String, url: String)` case.

**Rendering:** Use `NSTextAttachment` with the loaded image. For local/relative paths, resolve against `document.baseURL`. For remote URLs, show the alt text as placeholder (no network access in the extension).

Constraints:
- The Quick Look extension is sandboxed with `com.apple.security.files.user-selected.read-only`. It receives file access to the previewed file's directory from the system, so relative image paths should work.
- Maximum rendered width: scale images to fit the preview width (max ~500pt).
- If the image can't be loaded, render `[alt text]` as fallback text in gray.

## Feature 3: YAML Front Matter

**Syntax:** A `---` delimited block at the very start of the file:
```markdown
---
title: My Document
date: 2026-04-04
tags: [markdown, preview]
---

# Actual content starts here
```

**Parsing:** In `parseBlocks`, before entering the main loop, check if the first non-empty line is `---`. If so, consume lines until the next `---` and store as a `MarkdownBlock.frontMatter(String)` block. This must happen BEFORE horizontal rule detection since both use `---`.

**Rendering:** Render the front matter as a subtle, collapsed-looking block: monospaced text in `secondaryLabelColor` with a light background, similar to code blocks but visually quieter. The content is displayed as-is (the raw YAML).

## File Changes

| File | Change |
|---|---|
| `MarkdownDocumentRenderer.swift` | Add `.image` and `.frontMatter` cases, nested list parsing, image loading, front matter parsing |
| `MarkdownDocumentRendererTests.swift` | Tests for nested lists, images, front matter |
| `Fixtures/Sample.md` | Add examples |

## Out of Scope

- Remote image loading (no network access in sandbox)
- YAML parsing into structured data (render raw text)
- Nested blockquotes
- Mixed list types within a single list (bullet inside ordered or vice versa at same level)
