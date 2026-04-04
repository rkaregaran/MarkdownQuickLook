# Batch 2: Rendering Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add YAML front matter handling, inline images, and nested lists to handle real-world markdown documents.

**Architecture:** Three independent features added to `MarkdownDocumentRenderer.swift`. YAML front matter is parsed before the main loop. Images add a new block type with `NSTextAttachment` rendering. Nested lists extend the existing `MarkdownListItem` with a `children` field and recursive rendering.

**Tech Stack:** Swift, AppKit (NSAttributedString, NSTextAttachment, NSImage), XCTest

---

### Task 1: YAML Front Matter

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add `.frontMatter` to the `MarkdownBlock` enum**

```swift
    case frontMatter(String)
```

- [ ] **Step 2: Add front matter parsing at the start of `parseBlocks`**

Insert after `var index = 0` but before the `while` loop (around line 136):

```swift
        // Parse YAML front matter before main loop.
        if index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            var fmLines: [String] = []
            var cursor = index + 1
            while cursor < lines.count {
                let line = lines[cursor]
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    blocks.append(.frontMatter(fmLines.joined(separator: "\n")))
                    index = cursor + 1
                    break
                }
                fmLines.append(line)
                cursor += 1
            }
            // If no closing ---, treat it as normal content (don't consume).
            if index == 0 { /* closing --- not found, fall through to normal parsing */ }
        }
```

Note: This must run BEFORE the `while` loop so that `---` at the start of a file is treated as front matter, not a horizontal rule.

- [ ] **Step 3: Add front matter rendering**

In the `append(_:to:baseURL:)` switch, add:

```swift
        case .frontMatter(let text):
            let scale = settings.textSizeLevel.scaleFactor
            let font = NSFont.monospacedSystemFont(ofSize: 11 * scale, weight: .regular)

            let textBlock = RoundedTextBlock()
            textBlock.backgroundColor = NSColor(white: 0.5, alpha: 0.08)
            textBlock.setContentWidth(100, type: .percentageValueType)
            let padding = 8 * scale
            for edge: NSRectEdge in [.minX, .maxX, .minY, .maxY] {
                textBlock.setWidth(padding, type: .absoluteValueType, for: .padding, edge: edge)
            }

            let style = NSMutableParagraphStyle()
            style.textBlocks = [textBlock]

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: style
            ]

            output.append(NSAttributedString(string: text, attributes: attributes))
```

- [ ] **Step 4: Write tests**

```swift
    func testRenderYAMLFrontMatterIsExtracted() throws {
        let payload = try renderDocument(
            """
            ---
            title: Test
            date: 2026-01-01
            ---

            # Heading
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertTrue(text.contains("title: Test"))
        XCTAssertTrue(text.contains("Heading"))
    }

    func testRenderFrontMatterUsesMonospacedFont() throws {
        let payload = try renderDocument(
            """
            ---
            key: value
            ---

            Body
            """
        ).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let fmRange = (rendered.string as NSString).range(of: "key: value")
        let font = rendered.attribute(.font, at: fmRange.location, effectiveRange: nil) as? NSFont

        XCTAssertTrue(font?.isFixedPitch == true)
    }

    func testRenderUnclosedFrontMatterTreatedAsNormalContent() throws {
        let payload = try renderDocument(
            """
            ---
            not front matter
            # Heading
            """
        ).payload

        let text = payload.attributedContent.string
        // The --- should be treated as a horizontal rule, "not front matter" as paragraph.
        XCTAssertTrue(text.contains("not front matter"))
    }
```

- [ ] **Step 5: Run tests**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```

- [ ] **Step 6: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: parse and render YAML front matter"
```

---

### Task 2: Images

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add `.image` to the `MarkdownBlock` enum**

```swift
    case image(alt: String, path: String)
```

- [ ] **Step 2: Add image detection method**

Add near the other detection methods:

```swift
    private func imageReference(from line: String) -> (alt: String, path: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("![") else { return nil }
        guard let closeBracket = trimmed.firstIndex(of: "]"),
              trimmed[trimmed.index(after: closeBracket)...].hasPrefix("("),
              let closeParen = trimmed.lastIndex(of: ")"),
              closeParen == trimmed.index(before: trimmed.endIndex) else { return nil }
        let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<closeBracket])
        let pathStart = trimmed.index(closeBracket, offsetBy: 2)
        let path = String(trimmed[pathStart..<closeParen])
        return (alt, path)
    }
```

- [ ] **Step 3: Add image parsing to `parseBlocks`**

Add BEFORE the paragraph fallback (so a line that is only an image reference becomes an image block, not a paragraph):

```swift
            if let img = imageReference(from: lines[index]),
               lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("![") {
                // Only treat as block image if the entire line is the image reference.
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if trimmed == "![\(img.alt)](\(img.path))" {
                    blocks.append(.image(alt: img.alt, path: img.path))
                    index += 1
                    continue
                }
            }
```

- [ ] **Step 4: Add image rendering**

In the `append` switch:

```swift
        case .image(let alt, let path):
            appendImage(alt: alt, path: path, baseURL: baseURL, to: output)
```

Add the `appendImage` method:

```swift
    private func appendImage(alt: String, path: String, baseURL: URL, to output: NSMutableAttributedString) {
        let scale = settings.textSizeLevel.scaleFactor
        let maxWidth: CGFloat = 500

        // Resolve the image URL relative to the document's directory.
        let imageURL: URL
        if path.hasPrefix("/") {
            imageURL = URL(fileURLWithPath: path)
        } else if path.hasPrefix("http://") || path.hasPrefix("https://") {
            // Remote images: show alt text as fallback (no network in sandbox).
            appendImageFallback(alt: alt, to: output)
            return
        } else {
            imageURL = baseURL.appendingPathComponent(path)
        }

        guard let image = NSImage(contentsOf: imageURL) else {
            appendImageFallback(alt: alt, to: output)
            return
        }

        // Scale to fit.
        let originalSize = image.size
        let scaledWidth = min(originalSize.width, maxWidth)
        let scaleFactor = scaledWidth / originalSize.width
        let scaledSize = NSSize(width: scaledWidth, height: originalSize.height * scaleFactor)

        let attachment = NSTextAttachment()
        let cell = NSTextAttachmentCell(imageCell: image)
        cell.image?.size = scaledSize
        attachment.attachmentCell = cell

        let imageString = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 10 * scale
        style.alignment = .center
        imageString.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: imageString.length))
        output.append(imageString)
    }

    private func appendImageFallback(alt: String, to output: NSMutableAttributedString) {
        let scale = settings.textSizeLevel.scaleFactor
        let text = alt.isEmpty ? "[image]" : "[\(alt)]"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: settings.fontFamily.font(ofSize: 13 * scale, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: bodyParagraphStyle()
        ]
        output.append(NSAttributedString(string: text, attributes: attributes))
    }
```

- [ ] **Step 5: Add image to `isBlockStart`**

```swift
        if imageReference(from: line) != nil,
           line.trimmingCharacters(in: .whitespaces).hasPrefix("![") {
            return true
        }
```

- [ ] **Step 6: Write tests**

```swift
    func testRenderImageFallbackForMissingFile() throws {
        let payload = try renderDocument("![Screenshot](nonexistent.png)").payload
        XCTAssertEqual(payload.attributedContent.string, "[Screenshot]")
    }

    func testRenderImageFallbackForRemoteURL() throws {
        let payload = try renderDocument("![Logo](https://example.com/logo.png)").payload
        XCTAssertEqual(payload.attributedContent.string, "[Logo]")
    }

    func testRenderImageFallbackWithEmptyAlt() throws {
        let payload = try renderDocument("![](missing.png)").payload
        XCTAssertEqual(payload.attributedContent.string, "[image]")
    }

    func testRenderInlineImageSyntaxInParagraphStaysInline() throws {
        let payload = try renderDocument("Text with ![img](pic.png) inside").payload
        // Image syntax inside a paragraph is NOT extracted as a block image.
        // It stays as inline text (AttributedString may handle it or show raw).
        XCTAssertTrue(payload.attributedContent.string.contains("Text with"))
    }
```

- [ ] **Step 7: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```

- [ ] **Step 8: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: add image rendering with local file support and alt text fallback"
```

---

### Task 3: Nested Lists

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add `children` field to `MarkdownListItem`**

```swift
struct MarkdownListItem: Sendable {
    let index: Int?
    let paragraphs: [String]
    let children: [MarkdownListItem]
}
```

- [ ] **Step 2: Fix all existing `MarkdownListItem` creation sites**

In `parseListItem` (the return at the end):
```swift
        return (MarkdownListItem(index: nil, paragraphs: paragraphs, children: []), cursor)
```

In `parseOrderedListItem` (the return at the end):
```swift
        return (MarkdownListItem(index: number, paragraphs: paragraphs, children: []), cursor)
```

- [ ] **Step 3: Update `parseListBlock` to handle nested items**

Replace the current `parseListBlock` method:

```swift
    private func parseListBlock(from lines: [String], startingAt index: Int) throws -> (items: [MarkdownListItem], nextIndex: Int)? {
        guard isBulletLine(lines[index]) else {
            return nil
        }

        let baseIndent = leadingSpaceCount(lines[index])
        var items: [MarkdownListItem] = []
        var cursor = index

        while cursor < lines.count {
            let line = lines[cursor]
            let lineIndent = leadingSpaceCount(line)

            // If this line is a bullet at the base indent level, parse a new item.
            guard isBulletLine(line), lineIndent == baseIndent else { break }

            try throwIfCancelled()
            let item = try parseListItemWithChildren(from: lines, startingAt: cursor, baseIndent: baseIndent, ordered: false)
            items.append(item.item)
            cursor = item.nextIndex
        }

        return items.isEmpty ? nil : (items, cursor)
    }
```

- [ ] **Step 4: Update `parseOrderedListBlock` similarly**

Replace the current `parseOrderedListBlock` method:

```swift
    private func parseOrderedListBlock(from lines: [String], startingAt index: Int) throws -> (items: [MarkdownListItem], nextIndex: Int)? {
        guard isOrderedListLine(lines[index]) else {
            return nil
        }

        let baseIndent = leadingSpaceCount(lines[index])
        var items: [MarkdownListItem] = []
        var cursor = index
        var itemNumber = 1

        while cursor < lines.count {
            let line = lines[cursor]
            let lineIndent = leadingSpaceCount(line)

            guard isOrderedListLine(line), lineIndent == baseIndent else { break }

            try throwIfCancelled()
            let item = try parseListItemWithChildren(from: lines, startingAt: cursor, baseIndent: baseIndent, ordered: true, number: itemNumber)
            items.append(item.item)
            cursor = item.nextIndex
            itemNumber += 1
        }

        return items.isEmpty ? nil : (items, cursor)
    }
```

- [ ] **Step 5: Add `parseListItemWithChildren` and `leadingSpaceCount`**

```swift
    private func leadingSpaceCount(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private func parseListItemWithChildren(
        from lines: [String],
        startingAt index: Int,
        baseIndent: Int,
        ordered: Bool,
        number: Int? = nil
    ) throws -> (item: MarkdownListItem, nextIndex: Int) {
        let firstLine: String
        if ordered {
            firstLine = orderedListContent(from: lines[index])?.content ?? ""
        } else {
            firstLine = bulletContent(from: lines[index]) ?? ""
        }

        var paragraphs: [String] = [firstLine]
        var cursor = index + 1
        var children: [MarkdownListItem] = []

        while cursor < lines.count {
            try throwIfCancelled()
            let line = lines[cursor]

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Blank line: check if next non-blank is a deeper list item or continuation.
                if let next = nextNonBlankLineIndex(in: lines, startingAt: cursor + 1) {
                    let nextIndent = leadingSpaceCount(lines[next])
                    if nextIndent > baseIndent && (isBulletLine(lines[next]) || isOrderedListLine(lines[next])) {
                        cursor = next
                        continue
                    }
                }
                break
            }

            let lineIndent = leadingSpaceCount(line)

            // Deeper indented bullet or ordered list — parse as children.
            if lineIndent > baseIndent && isBulletLine(line) {
                let nested = try parseListBlock(from: lines, startingAt: cursor)
                if let nested = nested {
                    children.append(contentsOf: nested.items)
                    cursor = nested.nextIndex
                    continue
                }
            }

            if lineIndent > baseIndent && isOrderedListLine(line) {
                let nested = try parseOrderedListBlock(from: lines, startingAt: cursor)
                if let nested = nested {
                    children.append(contentsOf: nested.items)
                    cursor = nested.nextIndex
                    continue
                }
            }

            // Same or less indent with a list marker — belongs to parent, stop.
            if isBulletLine(line) || isOrderedListLine(line) {
                break
            }

            if isBlockStart(line) {
                break
            }

            // Continuation text.
            if lineIndent > baseIndent {
                let content = line.trimmingCharacters(in: .whitespaces)
                let last = paragraphs.count - 1
                paragraphs[last] = paragraphs[last] + " " + content
                cursor += 1
                continue
            }

            break
        }

        let itemIndex = ordered ? (number ?? 1) : nil
        return (MarkdownListItem(index: itemIndex, paragraphs: paragraphs, children: children), cursor)
    }
```

- [ ] **Step 6: Delete old `parseListItem` and `parseOrderedListItem`**

These are now replaced by `parseListItemWithChildren`. Remove them.

- [ ] **Step 7: Update list rendering to handle depth**

Replace the entire `.list` case in `append` with a call to a recursive helper:

```swift
        case .list(let items):
            appendListItems(items, depth: 0, baseURL: baseURL, to: output)
```

Add the recursive helper method:

```swift
    private func appendListItems(_ items: [MarkdownListItem], depth: Int, baseURL: URL, to output: NSMutableAttributedString) {
        let bullets = ["•", "◦", "▪"]

        for (itemIndex, item) in items.enumerated() {
            for (paragraphIndex, paragraph) in item.paragraphs.enumerated() {
                if paragraphIndex == 0 {
                    let (bullet, text): (String, String)
                    if let number = item.index {
                        (bullet, text) = ("\(number).", paragraph)
                    } else {
                        let (cb, ct) = checkboxBullet(for: paragraph)
                        if cb == "•" {
                            (bullet, text) = (bullets[min(depth, bullets.count - 1)], ct)
                        } else {
                            (bullet, text) = (cb, ct)
                        }
                    }
                    appendInlineMarkdown("\(bullet) \(text)", baseURL: baseURL, baseAttributes: hangingIndentAttributes(foregroundColor: NSColor.labelColor, depth: depth), to: output)
                } else {
                    output.append(NSAttributedString(string: "\n\n"))
                    appendInlineMarkdown(paragraph, baseURL: baseURL, baseAttributes: listContinuationParagraphAttributes(), to: output)
                }
            }

            // Render children.
            if !item.children.isEmpty {
                output.append(NSAttributedString(string: "\n"))
                appendListItems(item.children, depth: depth + 1, baseURL: baseURL, to: output)
            }

            if itemIndex < items.count - 1 {
                output.append(NSAttributedString(string: "\n"))
            }
        }
    }
```

- [ ] **Step 8: Add depth-aware `hangingIndentAttributes`**

Add an overload that accepts depth:

```swift
    private func hangingIndentAttributes(foregroundColor: NSColor, depth: Int) -> [NSAttributedString.Key: Any] {
        let scale = settings.textSizeLevel.scaleFactor
        let baseIndent = 24 * scale
        let depthIndent = CGFloat(depth) * 20 * scale
        let totalIndent = baseIndent + depthIndent

        let paragraph = bodyParagraphStyle()
        paragraph.firstLineHeadIndent = totalIndent
        paragraph.headIndent = totalIndent

        return [
            .font: settings.fontFamily.font(ofSize: 15 * scale, weight: .regular),
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraph
        ]
    }
```

Update the existing `hangingIndentAttributes(foregroundColor:)` (no depth) to call the new one:

```swift
    private func hangingIndentAttributes(foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
        hangingIndentAttributes(foregroundColor: foregroundColor, depth: 0)
    }
```

- [ ] **Step 9: Write tests**

```swift
    func testRenderNestedBulletList() throws {
        let payload = try renderDocument(
            """
            - Top
              - Nested
              - Nested 2
            - Back to top
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertTrue(text.contains("Top"))
        XCTAssertTrue(text.contains("Nested"))
        XCTAssertTrue(text.contains("Back to top"))
        // Nested items use different bullet.
        XCTAssertTrue(text.contains("◦"))
    }

    func testRenderDeeplyNestedList() throws {
        let payload = try renderDocument(
            """
            - Level 0
              - Level 1
                - Level 2
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertTrue(text.contains("•"))
        XCTAssertTrue(text.contains("◦"))
        XCTAssertTrue(text.contains("▪"))
    }

    func testRenderNestedOrderedList() throws {
        let payload = try renderDocument(
            """
            1. First
               1. Sub-first
               2. Sub-second
            2. Second
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertTrue(text.contains("1. First"))
        XCTAssertTrue(text.contains("1. Sub-first"))
        XCTAssertTrue(text.contains("2. Second"))
    }
```

- [ ] **Step 10: Run tests**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```

- [ ] **Step 11: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: add nested list support with depth-based indentation and bullet alternation"
```

---

### Task 4: Update Fixtures and Final Verification

**Files:**
- Modify: `Fixtures/Sample.md`

- [ ] **Step 1: Update Sample.md with new features**

Add to the end of `Fixtures/Sample.md`:

```markdown

## Nested Lists

- Fruits
  - Apples
  - Bananas
    - Yellow
    - Green
- Vegetables

## Image Test

![Sample Image](../MarkdownQuickLookApp/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png)
```

- [ ] **Step 2: Create a front matter test fixture**

Create `Fixtures/FrontMatter.md`:

```markdown
---
title: Front Matter Example
date: 2026-04-04
tags: [markdown, preview, test]
---

# Document with Front Matter

This document has YAML front matter at the top.
```

- [ ] **Step 3: Build and install**

```bash
./Scripts/build-release.sh
rm -rf /Applications/MarkdownQuickLook.app
ditto dist/MarkdownQuickLook.app /Applications/MarkdownQuickLook.app
open /Applications/MarkdownQuickLook.app
sleep 3
pluginkit -e use -i com.rzkr.MarkdownQuickLook.app.preview
qlmanage -r
```

- [ ] **Step 4: Visual verification**

Quick Look both `Fixtures/Sample.md` and `Fixtures/FrontMatter.md`. Verify:
- Nested lists show increasing indentation with alternating bullets (•, ◦, ▪)
- App icon image renders in the preview
- Front matter shows as subtle monospaced block
- All existing features still work

- [ ] **Step 5: Run all test suites**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

- [ ] **Step 6: Commit**

```bash
git add Fixtures/Sample.md Fixtures/FrontMatter.md
git commit -m "feat: update fixtures with nested lists, images, and front matter examples"
```
