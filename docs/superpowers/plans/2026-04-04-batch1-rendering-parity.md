# Batch 1: Rendering Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add horizontal rules, ordered lists, strikethrough, and verify dark mode to reach feature parity with free markdown Quick Look competitors.

**Architecture:** All four features are additive changes to `MarkdownDocumentRenderer.swift` and its test file. Horizontal rules and ordered lists add new block types and parsing. Strikethrough is a post-processing step on existing inline rendering. Dark mode is verification-only.

**Tech Stack:** Swift, AppKit (NSAttributedString, NSFont, NSColor), XCTest

---

### Task 1: Horizontal Rules

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add `.horizontalRule` to the `MarkdownBlock` enum**

In `MarkdownDocumentRenderer.swift`, add the new case to the enum (currently at line 27):

```swift
enum MarkdownBlock: Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote([String])
    case list([MarkdownListItem])
    case code(language: String?, text: String)
    case table(MarkdownTable)
    case horizontalRule
}
```

- [ ] **Step 2: Add the horizontal rule detection method**

Add after the `isBulletLine` method (around line 828):

```swift
    private func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        guard let char = stripped.first, ["-", "*", "_"].contains(char) else { return false }
        return stripped.allSatisfy { $0 == char }
    }
```

- [ ] **Step 3: Add horizontal rule parsing to `parseBlocks`**

In `parseBlocks`, add horizontal rule detection AFTER the heading check but BEFORE the quote check (around line 155). This ordering prevents `---` from being eaten by the paragraph parser, and avoids conflict with list bullets (`* ` requires a space + content):

```swift
            if isHorizontalRule(lines[index]) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }
```

- [ ] **Step 4: Add horizontal rule to `isBlockStart`**

In the `isBlockStart` method, add before the `return false`:

```swift
        if isHorizontalRule(line) {
            return true
        }
```

- [ ] **Step 5: Add horizontal rule rendering to `append`**

In the `append(_:to:baseURL:)` switch statement, add the case:

```swift
        case .horizontalRule:
            let scale = settings.textSizeLevel.scaleFactor
            let rule = NSMutableAttributedString(string: "\u{200B}")
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = 8 * scale
            style.paragraphSpacing = 8 * scale
            let textBlock = HorizontalRuleTextBlock()
            textBlock.setContentWidth(100, type: .percentageValueType)
            textBlock.setWidth(8 * scale, type: .absoluteValueType, for: .padding, edge: .minY)
            style.textBlocks = [textBlock]
            rule.addAttributes([
                .paragraphStyle: style,
                .font: NSFont.systemFont(ofSize: 1)
            ], range: NSRange(location: 0, length: rule.length))
            output.append(rule)
```

- [ ] **Step 6: Add the `HorizontalRuleTextBlock` class**

Add at the bottom of the file, next to the other `NSTextBlock` subclasses:

```swift
private final class HorizontalRuleTextBlock: NSTextBlock {
    override func drawBackground(
        withFrame frameRect: NSRect,
        in controlView: NSView?,
        characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        NSColor.separatorColor.setFill()
        let lineRect = NSRect(x: frameRect.minX, y: frameRect.midY, width: frameRect.width, height: 1)
        lineRect.fill()
    }
}
```

- [ ] **Step 7: Write tests**

Add to `MarkdownDocumentRendererTests.swift`:

```swift
    func testRenderHorizontalRuleWithDashes() throws {
        let payload = try renderDocument(
            """
            Before

            ---

            After
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertTrue(text.contains("Before"))
        XCTAssertTrue(text.contains("After"))
        // Horizontal rule renders as zero-width space separator.
        XCTAssertTrue(text.contains("\u{200B}"))
    }

    func testRenderHorizontalRuleWithAsterisks() throws {
        let payload = try renderDocument("***").payload
        XCTAssertTrue(payload.attributedContent.string.contains("\u{200B}"))
    }

    func testRenderHorizontalRuleWithUnderscores() throws {
        let payload = try renderDocument("___").payload
        XCTAssertTrue(payload.attributedContent.string.contains("\u{200B}"))
    }

    func testRenderDoesNotTreatShortDashLineAsRule() throws {
        let payload = try renderDocument("--").payload
        XCTAssertTrue(payload.attributedContent.string.contains("--"))
        XCTAssertFalse(payload.attributedContent.string.contains("\u{200B}"))
    }
```

- [ ] **Step 8: Run tests**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: add horizontal rule rendering (---, ***, ___)"
```

---

### Task 2: Ordered Lists

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add `index` field to `MarkdownListItem`**

```swift
struct MarkdownListItem: Sendable {
    let index: Int?
    let paragraphs: [String]
}
```

- [ ] **Step 2: Fix existing call sites**

Every place that creates a `MarkdownListItem` needs the new `index` parameter. In `parseListItem` (around line 304):

```swift
        return (MarkdownListItem(index: nil, paragraphs: paragraphs), cursor)
```

- [ ] **Step 3: Add ordered list detection**

Add after `bulletContent(from:)` (around line 847):

```swift
    private func orderedListContent(from line: String) -> (index: Int, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let numberPart = trimmed[trimmed.startIndex..<dotIndex]
        guard let number = Int(numberPart), number >= 0 else { return nil }
        let afterDot = trimmed[trimmed.index(after: dotIndex)...]
        guard afterDot.hasPrefix(" ") else { return nil }
        return (number, String(afterDot.dropFirst()))
    }

    private func isOrderedListLine(_ line: String) -> Bool {
        orderedListContent(from: line) != nil
    }
```

- [ ] **Step 4: Add ordered list parsing to `parseBlocks`**

Add after the bullet list check in `parseBlocks` (around line 166):

```swift
            if let orderedList = try parseOrderedListBlock(from: lines, startingAt: index) {
                blocks.append(.list(orderedList.items))
                index = orderedList.nextIndex
                continue
            }
```

- [ ] **Step 5: Add `parseOrderedListBlock` and `parseOrderedListItem` methods**

Add after `parseListItem`:

```swift
    private func parseOrderedListBlock(from lines: [String], startingAt index: Int) throws -> (items: [MarkdownListItem], nextIndex: Int)? {
        guard isOrderedListLine(lines[index]) else {
            return nil
        }

        var items: [MarkdownListItem] = []
        var cursor = index
        var itemNumber = 1

        while cursor < lines.count, isOrderedListLine(lines[cursor]) {
            try throwIfCancelled()
            let item = try parseOrderedListItem(from: lines, startingAt: cursor, number: itemNumber)
            items.append(item.item)
            cursor = item.nextIndex
            itemNumber += 1
        }

        return (items, cursor)
    }

    private func parseOrderedListItem(from lines: [String], startingAt index: Int, number: Int) throws -> (item: MarkdownListItem, nextIndex: Int) {
        let content = orderedListContent(from: lines[index])
        let firstLine = content?.content ?? ""
        var paragraphs: [String] = []
        var currentParagraph = firstLine
        var cursor = index + 1

        while cursor < lines.count {
            try throwIfCancelled()
            let line = lines[cursor]

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let nextNonBlankIndex = nextNonBlankLineIndex(in: lines, startingAt: cursor + 1),
                   isContinuationParagraphLine(lines[nextNonBlankIndex]) {
                    if currentParagraph.isEmpty == false {
                        paragraphs.append(currentParagraph)
                    }
                    currentParagraph = ""
                    cursor = nextNonBlankIndex
                    continue
                }

                break
            }

            if isBlockStart(line) || isOrderedListLine(line) {
                break
            }

            guard isContinuationParagraphLine(line) else {
                break
            }

            let trimmedContent = line.trimmingCharacters(in: .whitespaces)

            if currentParagraph.isEmpty {
                currentParagraph = trimmedContent
            } else {
                currentParagraph += " " + trimmedContent
            }

            cursor += 1
        }

        if currentParagraph.isEmpty == false {
            paragraphs.append(currentParagraph)
        }

        return (MarkdownListItem(index: number, paragraphs: paragraphs), cursor)
    }
```

- [ ] **Step 6: Add ordered list to `isBlockStart`**

```swift
        if isOrderedListLine(line) {
            return true
        }
```

- [ ] **Step 7: Update list rendering to use `index` for numbered items**

In the `append` method's `.list` case, update the bullet selection logic. Replace the current `checkboxBullet` call:

```swift
        case .list(let items):
            for (itemIndex, item) in items.enumerated() {
                for (paragraphIndex, paragraph) in item.paragraphs.enumerated() {
                    if paragraphIndex == 0 {
                        let (bullet, text): (String, String)
                        if let number = item.index {
                            (bullet, text) = ("\(number).", paragraph)
                        } else {
                            (bullet, text) = checkboxBullet(for: paragraph)
                        }
                        appendInlineMarkdown("\(bullet) \(text)", baseURL: baseURL, baseAttributes: hangingIndentAttributes(foregroundColor: NSColor.labelColor), to: output)
                    } else {
                        output.append(NSAttributedString(string: "\n\n"))
                        appendInlineMarkdown(paragraph, baseURL: baseURL, baseAttributes: listContinuationParagraphAttributes(), to: output)
                    }
                }

                if itemIndex < items.count - 1 {
                    output.append(NSAttributedString(string: "\n"))
                }
            }
```

- [ ] **Step 8: Write tests**

```swift
    func testRenderOrderedList() throws {
        let payload = try renderDocument(
            """
            1. First item
            2. Second item
            3. Third item
            """
        ).payload

        XCTAssertEqual(
            payload.attributedContent.string,
            "1. First item\n2. Second item\n3. Third item"
        )
    }

    func testRenderOrderedListRenumbersSequentially() throws {
        let payload = try renderDocument(
            """
            5. Actually first
            10. Actually second
            """
        ).payload

        XCTAssertEqual(
            payload.attributedContent.string,
            "1. Actually first\n2. Actually second"
        )
    }

    func testRenderDoesNotTreatNumberWithoutDotAsOrderedList() throws {
        let payload = try renderDocument("123 not a list").payload
        XCTAssertEqual(payload.attributedContent.string, "123 not a list")
    }
```

- [ ] **Step 9: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```

Expected: all tests pass.

- [ ] **Step 10: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: add ordered list rendering (1. 2. 3.)"
```

---

### Task 3: Strikethrough

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Add strikethrough post-processing to `inlineMarkdownAttributedString`**

Replace the current `inlineMarkdownAttributedString` method (around line 430):

```swift
    private func inlineMarkdownAttributedString(
        from text: String,
        baseURL: URL,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSMutableAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: text, options: options, baseURL: baseURL)) ?? AttributedString(text)
        let attributed = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))
        applyStrikethrough(to: attributed, from: parsed)
        return attributed
    }
```

- [ ] **Step 2: Add the `applyStrikethrough` method**

Add after `inlineMarkdownAttributedString`:

```swift
    private func applyStrikethrough(to attributed: NSMutableAttributedString, from source: AttributedString) {
        for run in source.runs {
            guard let intent = run.inlinePresentationIntent, intent.contains(.strikethrough) else { continue }
            let nsRange = NSRange(run.range, in: source)
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }
```

- [ ] **Step 3: Write tests**

```swift
    func testRenderStrikethroughAppliesStrikethroughStyle() throws {
        let payload = try renderDocument("Hello ~~struck~~ world").payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString
        let struckRange = nsString.range(of: "struck")

        XCTAssertNotEqual(struckRange.location, NSNotFound)
        let style = rendered.attribute(.strikethroughStyle, at: struckRange.location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testRenderNonStrikethroughTextHasNoStrikethroughStyle() throws {
        let payload = try renderDocument("Hello ~~struck~~ world").payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let style = rendered.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertNil(style)
    }
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: add strikethrough rendering (~~text~~)"
```

---

### Task 4: Dark Mode Verification & Sample Update

**Files:**
- Modify: `Fixtures/Sample.md`

- [ ] **Step 1: Update Sample.md with all new features**

Replace `Fixtures/Sample.md`:

```markdown
# Markdown Quick Look

This file checks the app's best-effort preview path for standard `.md` files.

## Checklist

- [x] Heading styling
- [x] Paragraph spacing
- [x] List bullets
- [ ] Ordered lists
- [x] [Link rendering](https://openai.com)

> If Finder still shows plain text, the extension may be registered correctly and macOS may still prefer the built-in preview.

```swift
let greeting = "hello, quick look"
print(greeting)
```

## Features

| Feature | Status | Notes |
|---------|--------|-------|
| Headings | Supported | h1 through h6 |
| Lists | Supported | Bullet and ordered |
| Code blocks | Supported | Fenced with syntax highlighting |
| Tables | Supported | Pipe-delimited |
| Strikethrough | Supported | ~~like this~~ |

---

## Ordered Steps

1. Select a .md file in Finder
2. Press Space to preview
3. Enjoy formatted markdown

This text has ~~strikethrough~~ and **bold** and *italic* formatting.
```

- [ ] **Step 2: Build and install**

```bash
./Scripts/build-release.sh
rm -rf /Applications/MarkdownQuickLook.app
ditto dist/MarkdownQuickLook.app /Applications/MarkdownQuickLook.app
open /Applications/MarkdownQuickLook.app
sleep 3
pluginkit -e use -i com.rzkr.MarkdownQuickLook.app.preview
qlmanage -r
```

- [ ] **Step 3: Verify in light mode**

Quick Look `Fixtures/Sample.md`. Verify:
- Headings render with correct sizes
- Bullet list with checkboxes renders
- Ordered list renders with numbers
- Code block has gray rounded background with syntax highlighting
- Table renders with aligned columns
- Horizontal rule shows as a thin line
- Strikethrough text has a line through it
- Blockquote has left border bar

- [ ] **Step 4: Verify in dark mode**

Switch to dark mode (System Settings > Appearance > Dark). Quick Look the same file. Verify:
- Background is dark
- Text is light and readable
- Code block background is visible but subtle
- Syntax highlighting colors are readable
- Quote border is visible
- Table separators are visible
- Horizontal rule is visible
- All colors adapt properly

- [ ] **Step 5: Commit**

```bash
git add Fixtures/Sample.md
git commit -m "feat: update sample fixture with ordered lists, strikethrough, and horizontal rules"
```

---

### Task 5: Update CRLF test for new features

**Files:**
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

The existing CRLF test hardcodes expected output. Horizontal rules and ordered lists may need to be tested with CRLF too.

- [ ] **Step 1: Add horizontal rule to the CRLF test input**

Update `testRenderTreatsCRLFInputLikeLFInputForSupportedBlocks` — add a horizontal rule and ordered list to the test markdown, and update the expected string accordingly. The key assertion is that CRLF and LF produce identical output — the exact expected string depends on the final rendering of all blocks. After implementing Tasks 1-3, run the CRLF test. If it fails, update the expected string to match the LF output.

- [ ] **Step 2: Run all tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

Expected: all pass.

- [ ] **Step 3: Commit if changes were needed**

```bash
git add MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "test: update CRLF test for horizontal rules and ordered lists"
```
