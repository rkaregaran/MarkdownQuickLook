# Batch 1: Rendering Parity — Design Spec

## Goal

Add four missing markdown features to reach parity with free competitors: horizontal rules, ordered lists, strikethrough, and dark mode verification.

## Feature 1: Horizontal Rules

**Syntax:** A line containing only three or more `-`, `*`, or `_` characters (optionally with spaces) produces a visual separator.

```markdown
---
***
___
```

**Parsing:** New `MarkdownBlock.horizontalRule` case. Detected in `parseBlocks` before the paragraph fallback. A line matches if, after trimming whitespace, it consists of three or more of the same character (`-`, `*`, or `_`) with optional spaces between them.

Must not conflict with:
- Heading syntax (`---` under text is setext heading, but we don't support setext headings so no conflict)
- List bullets (`- ` requires a space + content after; `---` has no content)

**Rendering:** A 1px horizontal line spanning the full width, using `NSColor.separatorColor` (auto-adapts to dark mode). Implemented as an `NSAttributedString` with a custom `NSTextAttachment` or a simple paragraph with a border, or a single-line string with a bottom border via `NSParagraphStyle`. Simplest approach: render a thin `NSTextAttachment` image.

## Feature 2: Ordered Lists

**Syntax:** Lines starting with a number, dot, and space: `1. `, `2. `, `10. `, etc.

```markdown
1. First item
2. Second item
3. Third item
```

**Parsing:** Extend `MarkdownBlock.list` to support ordered items. Add a `MarkdownListItem.isOrdered` flag or a separate `MarkdownBlock.orderedList` case. The simplest approach: add an `ordered: Bool` flag to the existing `.list` case, and an `index: Int?` field to `MarkdownListItem`.

Detection: a line where the trimmed content matches `^\d+\.\s`. Parse the number to display it.

Continuation lines work the same as bullet lists (indented lines following the first).

**Rendering:** Same as bullet lists but with `1.`, `2.`, `3.` instead of `•`. Use the hanging indent style already in place — just swap the bullet character for the number + period.

## Feature 3: Strikethrough

**Syntax:** `~~struck text~~`

**Parsing:** No block-level changes needed. Apple's `AttributedString(markdown:)` already parses `~~text~~` into `InlinePresentationIntent.strikethrough` (rawValue 32). The issue is that this intent is not being converted to `NSAttributedString.Key.strikethroughStyle` during rendering.

**Fix:** After calling `inlineMarkdownAttributedString(from:baseURL:baseAttributes:)`, post-process the result to find any ranges with `InlinePresentationIntent.strikethrough` and apply `NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.single.rawValue`.

This is a small change in one method — no new block types or parsing logic needed.

## Feature 4: Dark Mode Verification

**Current state:** The renderer uses semantic colors throughout:
- `NSColor.labelColor` for body text and headings
- `NSColor.secondaryLabelColor` for quotes and comments
- `NSColor.separatorColor` available for rules
- `NSColor.textBackgroundColor` for the preview background
- Code block background: `NSColor(white: 0.5, alpha: 0.12)` — semi-transparent, adapts automatically
- Syntax highlighting colors: `NSColor.systemGreen`, `.systemPink`, `.systemBlue`, `.systemPurple` — all auto-adapt
- Quote border: `NSColor.tertiaryLabelColor` — auto-adapts

**Expected result:** Dark mode should already work correctly. This feature is a verification pass, not an implementation task.

**Verification:** Build, install, switch to dark mode in System Settings, Quick Look a `.md` file. Check:
1. Background is dark
2. Text is light
3. Code blocks have visible but subtle background
4. Syntax highlighting colors are readable
5. Quote border is visible
6. Table separators are visible

If anything looks wrong, fix the specific color. No architectural changes expected.

## File Changes

| File | Change |
|---|---|
| `MarkdownDocumentRenderer.swift` | Add `.horizontalRule` case, ordered list parsing, strikethrough post-processing, horizontal rule detection |
| `MarkdownDocumentRendererTests.swift` | Tests for horizontal rules, ordered lists, strikethrough |
| `Fixtures/Sample.md` | Add examples of new features |

## Out of Scope

- Setext-style headings (`===` / `---` underlines)
- Nested lists (Batch 2)
- Images (Batch 2)
- YAML front matter (Batch 2)
