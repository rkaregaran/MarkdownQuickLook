# Phase 1: Markdown Parser Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub-style alert blockquotes, footnotes, table column alignment, indented code blocks, reference-style links, TOML front matter, code-fence info-string parsing, RTL paragraph direction, smart-dashes toggle, and expanded UTI support to reach Markdown ecosystem parity with `pluk-inc/markdown-preview` without leaving the `NSTextView` pipeline.

**Architecture:** All parser additions plug into `MarkdownDocumentRenderer.swift` — extend the `MarkdownBlock` enum, add per-feature parse functions called from `parseBlocks`, extend `append(_:to:baseURL:)` rendering. The fence info-string change rewires `parseFencedCodeBlock` to extract structured info. UTI support is a pure `Info.plist` edit across three targets. RTL detection is a small helper added to the inline rendering path.

**Tech Stack:** Swift, AppKit (`NSAttributedString`, `NSTextTable`, `NSParagraphStyle`, `NSColor.systemBlue/Yellow/Red/Green/Purple`), XCTest, `UserDefaults` via the existing `MarkdownRenderSettings`.

**Spec:** `docs/superpowers/specs/2026-05-23-pluk-gap-roadmap-design.md` § Phase 1.

---

### Task 1: GitHub-style alert blockquotes

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`
- Create: `Fixtures/Pluk-Parity/alerts.md`

- [ ] **Step 1: Add the alert kind enum and new block case**

In `MarkdownDocumentRenderer.swift`, add a new file-private enum near the other markdown types (around line 50, after `MarkdownTable`):

```swift
enum MarkdownAlertKind: String, Sendable {
    case note, tip, important, warning, caution

    var displayTitle: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .note: return .systemBlue
        case .tip: return .systemGreen
        case .important: return .systemPurple
        case .warning: return .systemYellow
        case .caution: return .systemRed
        }
    }
}
```

Then extend the `MarkdownBlock` enum (currently line 34-44) with the new case:

```swift
enum MarkdownBlock: Sendable {
    case frontMatter(String)
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote([String])
    case alert(kind: MarkdownAlertKind, title: String?, paragraphs: [String])
    case list([MarkdownListItem])
    case code(language: String?, text: String)
    case table(MarkdownTable)
    case horizontalRule
    case image(alt: String, path: String)
}
```

- [ ] **Step 2: Write the failing test**

Add to `MarkdownDocumentRendererTests.swift`:

```swift
func testRenderParsesNoteAlert() throws {
    let payload = try renderDocument(
        """
        > [!NOTE]
        > Heads up.
        """
    ).payload

    XCTAssertTrue(
        payload.attributedContent.string.contains("Note"),
        "expected alert title 'Note' in output"
    )
    XCTAssertTrue(
        payload.attributedContent.string.contains("Heads up."),
        "expected body 'Heads up.' in output"
    )
}

func testRenderParsesWarningAlertWithCustomTitle() throws {
    let payload = try renderDocument(
        """
        > [!WARNING] Read this first
        > Mind the gap.
        """
    ).payload

    let s = payload.attributedContent.string
    XCTAssertTrue(s.contains("Read this first"), "expected custom title")
    XCTAssertTrue(s.contains("Mind the gap."))
    XCTAssertFalse(s.contains("[!WARNING]"), "raw marker should be stripped")
}

func testRenderUnknownAlertMarkerFallsBackToQuote() throws {
    let payload = try renderDocument(
        """
        > [!FOO]
        > Body.
        """
    ).payload

    XCTAssertTrue(
        payload.attributedContent.string.contains("[!FOO]"),
        "unknown alert marker should render as literal quote text"
    )
}
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderParsesNoteAlert
```

Expected: FAIL (alert is parsed as a quote so the assertions on "Note" / no `[!WARNING]` should miss).

- [ ] **Step 4: Add the alert detector**

Add this private function inside `MarkdownDocumentRenderer` (near `parseQuoteBlock` around line 330):

```swift
private static let alertMarkerRegex: NSRegularExpression = {
    // swiftlint:disable:next force_try
    try! NSRegularExpression(
        pattern: #"^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](?:\s+(.+))?$"#,
        options: [.caseInsensitive]
    )
}()

private func parseAlertBlock(from lines: [String], startingAt index: Int) throws -> (alert: (kind: MarkdownAlertKind, title: String?, paragraphs: [String]), nextIndex: Int)? {
    guard let quote = try parseQuoteBlock(from: lines, startingAt: index) else { return nil }
    guard let firstParagraph = quote.paragraphs.first else { return nil }

    let trimmedFirst = firstParagraph.trimmingCharacters(in: .whitespaces)
    let nsFirst = trimmedFirst as NSString
    let fullRange = NSRange(location: 0, length: nsFirst.length)

    // Marker must occupy the entire first line (CommonMark-ish).
    // The first paragraph as produced by parseQuoteBlock has space-joined lines,
    // so we match the prefix only.
    guard let match = Self.alertMarkerRegex.firstMatch(in: trimmedFirst, options: .anchored, range: fullRange) else {
        return nil
    }

    let kindRaw = nsFirst.substring(with: match.range(at: 1)).lowercased()
    guard let kind = MarkdownAlertKind(rawValue: kindRaw) else { return nil }

    let titleRange = match.range(at: 2)
    let title: String? = titleRange.location == NSNotFound
        ? nil
        : nsFirst.substring(with: titleRange)

    // Drop the marker from the first paragraph; if that leaves it empty, drop the paragraph too.
    var paragraphs = quote.paragraphs
    let markerLength = match.range.length
    let firstBody = String(trimmedFirst.dropFirst(markerLength)).trimmingCharacters(in: .whitespaces)
    if firstBody.isEmpty {
        paragraphs.removeFirst()
    } else {
        paragraphs[0] = firstBody
    }

    return ((kind, title, paragraphs), quote.nextIndex)
}
```

- [ ] **Step 5: Wire the detector into `parseBlocks`**

In `parseBlocks` (currently around line 264, right before `parseQuoteBlock`), insert the alert detector. The alert detector must run *before* the quote detector because alerts ARE quotes structurally:

```swift
            if let alert = try parseAlertBlock(from: lines, startingAt: index) {
                blocks.append(.alert(kind: alert.alert.kind, title: alert.alert.title, paragraphs: alert.alert.paragraphs))
                index = alert.nextIndex
                continue
            }

            if let quote = try parseQuoteBlock(from: lines, startingAt: index) {
                blocks.append(.quote(quote.paragraphs))
                index = quote.nextIndex
                continue
            }
```

- [ ] **Step 6: Add the renderer case**

In the `append(_:to:baseURL:)` switch (around line 571), add a case for `.alert`:

```swift
        case .alert(let kind, let title, let paragraphs):
            appendAlert(kind: kind, title: title, paragraphs: paragraphs, baseURL: baseURL, to: output)
```

- [ ] **Step 7: Implement `appendAlert`**

Add near `appendTable` (around line 860):

```swift
private func appendAlert(
    kind: MarkdownAlertKind,
    title: String?,
    paragraphs: [String],
    baseURL: URL,
    to output: NSMutableAttributedString
) {
    let scale = settings.textSizeLevel.scaleFactor

    // Header line: "● Note" or "● Custom title"
    let displayedTitle = title ?? kind.displayTitle
    let headerString = NSMutableAttributedString(string: "● \(displayedTitle)\n", attributes: [
        .font: settings.fontFamily.font(ofSize: 13 * scale, weight: .semibold),
        .foregroundColor: kind.tintColor,
        .paragraphStyle: alertHeaderParagraphStyle(tint: kind.tintColor)
    ])

    output.append(headerString)

    // Body: render each paragraph as quote-styled text with the same tinted border.
    let body = paragraphs.joined(separator: "\n\n")
    let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: settings.fontFamily.font(ofSize: 15 * scale, weight: .regular),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: alertBodyParagraphStyle(tint: kind.tintColor)
    ]
    appendInlineMarkdown(body, baseURL: baseURL, baseAttributes: bodyAttrs, to: output)
}

private func alertHeaderParagraphStyle(tint: NSColor) -> NSParagraphStyle {
    let style = bodyParagraphStyle()
    let block = TintedBorderTextBlock(tint: tint)
    block.setContentWidth(100, type: .percentageValueType)
    block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
    block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minY)
    style.textBlocks = [block]
    return style
}

private func alertBodyParagraphStyle(tint: NSColor) -> NSParagraphStyle {
    let style = bodyParagraphStyle()
    let block = TintedBorderTextBlock(tint: tint)
    block.setContentWidth(100, type: .percentageValueType)
    block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
    block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .minY)
    block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxY)
    style.textBlocks = [block]
    return style
}
```

- [ ] **Step 8: Add the `TintedBorderTextBlock`**

Find the existing `QuoteBorderTextBlock` (search the file for `private final class QuoteBorderTextBlock`) and add a parallel class beside it:

```swift
private final class TintedBorderTextBlock: NSTextBlock {
    let tint: NSColor
    init(tint: NSColor) {
        self.tint = tint
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func drawBackground(
        withFrame frameRect: NSRect,
        in controlView: NSView,
        characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        let bar = NSRect(x: frameRect.minX, y: frameRect.minY, width: 3, height: frameRect.height)
        tint.withAlphaComponent(0.85).setFill()
        bar.fill()
    }
}
```

- [ ] **Step 9: Update `instrumentationName` for the new block**

In `MarkdownDocumentRenderer.swift`, find `var instrumentationName: String` on `MarkdownBlock` (used in `#if DEBUG` perf logging). Add the new case:

```swift
        case .alert: return "alert"
```

- [ ] **Step 10: Run tests to confirm they pass**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderParsesNoteAlert -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderParsesWarningAlertWithCustomTitle -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderUnknownAlertMarkerFallsBackToQuote
```

Expected: 3 tests PASS.

- [ ] **Step 11: Create the fixture and visually verify**

Create `Fixtures/Pluk-Parity/alerts.md`:

```markdown
# Alert blockquotes

> [!NOTE]
> Useful information that users should know, even when skimming content.

> [!TIP]
> Helpful advice for doing things better or more easily.

> [!IMPORTANT]
> Key information users need to know to achieve their goal.

> [!WARNING] Read this first
> Urgent info that needs immediate user attention to avoid problems.

> [!CAUTION]
> Advises about risks or negative outcomes of certain actions.

> [!FOO]
> Unknown marker — should render as plain quote.
```

Then preview it in Quick Look:

```bash
qlmanage -p Fixtures/Pluk-Parity/alerts.md
```

Expected: each kind shows its tinted left border and label; the `[!FOO]` block is a plain blockquote.

- [ ] **Step 12: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift Fixtures/Pluk-Parity/alerts.md
git commit -m "$(cat <<'EOF'
feat: render GitHub-style alert blockquotes

Detects [!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION] markers
on the first line of a blockquote and renders them as labeled callouts
with a tinted left border. Unknown markers fall back to plain quotes.
EOF
)"
```

---

### Task 2: Footnotes

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`
- Create: `Fixtures/Pluk-Parity/footnotes.md`

- [ ] **Step 1: Add footnote data structures and block cases**

In `MarkdownDocumentRenderer.swift`, near the other markdown types, add:

```swift
struct MarkdownFootnoteDefinition: Sendable {
    let id: String           // raw label, e.g. "1" or "alpha"
    let number: Int          // 1-based assigned during pre-pass
    let paragraphs: [String]
}
```

Extend `MarkdownBlock`:

```swift
    case footnotesSection([MarkdownFootnoteDefinition])
```

- [ ] **Step 2: Write the failing test**

Add to the test file:

```swift
func testRenderInlineFootnoteReferenceIsSuperscript() throws {
    let payload = try renderDocument(
        """
        Body text[^1].

        [^1]: First note.
        """
    ).payload

    let s = payload.attributedContent.string
    XCTAssertTrue(s.contains("Body text"), "body present")
    XCTAssertTrue(s.contains("¹") || s.contains("[1]"), "reference rendered as numeric marker")
    XCTAssertTrue(s.contains("First note."), "footnote definition rendered in section")
    XCTAssertFalse(s.contains("[^1]"), "raw markdown reference should be replaced")
}

func testRenderUndefinedFootnoteReferenceRendersLiteral() throws {
    let payload = try renderDocument("Body[^missing].").payload
    XCTAssertTrue(
        payload.attributedContent.string.contains("[^missing]"),
        "undefined reference must render literally"
    )
}

func testRenderRendersFootnoteSectionInDocumentOrder() throws {
    let payload = try renderDocument(
        """
        First[^a] then second[^b].

        [^b]: Beta.
        [^a]: Alpha.
        """
    ).payload

    let s = payload.attributedContent.string
    let alphaIdx = (s as NSString).range(of: "Alpha.").location
    let betaIdx = (s as NSString).range(of: "Beta.").location
    XCTAssertNotEqual(alphaIdx, NSNotFound)
    XCTAssertNotEqual(betaIdx, NSNotFound)
    XCTAssertLessThan(alphaIdx, betaIdx, "Alpha referenced first should render first in section")
}
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderInlineFootnoteReferenceIsSuperscript
```

Expected: FAIL (footnotes not parsed; `[^1]` and `[^1]: ...` render literally).

- [ ] **Step 4: Add the definition pre-pass**

Add a new private function in `MarkdownDocumentRenderer`:

```swift
private static let footnoteDefinitionRegex: NSRegularExpression = {
    try! NSRegularExpression(pattern: #"^\[\^([^\]]+)\]:\s*(.*)$"#)
}()

/// Strips `[^id]: text` lines (and their indented continuation lines) from the
/// document and returns (cleanedLines, definitionsByID).
private func extractFootnoteDefinitions(from lines: [String]) -> (cleaned: [String], definitions: [String: [String]]) {
    var cleaned: [String] = []
    var definitions: [String: [String]] = [:]
    var index = 0

    while index < lines.count {
        let line = lines[index]
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        if let match = Self.footnoteDefinitionRegex.firstMatch(in: line, options: .anchored, range: range) {
            let id = nsLine.substring(with: match.range(at: 1))
            var paragraphs: [String] = []
            var currentLines: [String] = [nsLine.substring(with: match.range(at: 2))]

            var cursor = index + 1
            while cursor < lines.count {
                let nextRaw = lines[cursor]
                if nextRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Blank — check whether next non-blank is indented continuation.
                    if let peek = nextNonBlankLineIndex(in: lines, startingAt: cursor + 1),
                       leadingSpaceCount(lines[peek]) >= 4,
                       Self.footnoteDefinitionRegex.firstMatch(in: lines[peek], options: .anchored, range: NSRange(location: 0, length: (lines[peek] as NSString).length)) == nil {
                        if !currentLines.isEmpty {
                            paragraphs.append(currentLines.joined(separator: " "))
                            currentLines.removeAll()
                        }
                        currentLines.append(lines[peek].trimmingCharacters(in: .whitespaces))
                        cursor = peek + 1
                        continue
                    }
                    break
                }
                if leadingSpaceCount(nextRaw) >= 4 {
                    currentLines.append(nextRaw.trimmingCharacters(in: .whitespaces))
                    cursor += 1
                    continue
                }
                break
            }

            if !currentLines.isEmpty {
                paragraphs.append(currentLines.joined(separator: " "))
            }

            definitions[id] = paragraphs
            index = cursor
            continue
        }

        cleaned.append(line)
        index += 1
    }

    return (cleaned, definitions)
}

private func nextNonBlankLineIndex(in lines: [String], startingAt index: Int) -> Int? {
    var i = index
    while i < lines.count {
        if !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return i }
        i += 1
    }
    return nil
}
```

(If `nextNonBlankLineIndex` already exists in this file, skip the duplicate.)

- [ ] **Step 5: Build the reference numbering**

Add:

```swift
private static let footnoteReferenceRegex: NSRegularExpression = {
    try! NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#)
}()

/// Scans cleaned lines in document order to build (id → number) mapping for
/// references that have matching definitions. Returns ordered definitions
/// for rendering, and a number lookup keyed by raw id.
private func resolveFootnoteOrder(
    cleanedLines: [String],
    definitions: [String: [String]]
) -> (ordered: [MarkdownFootnoteDefinition], numbersByID: [String: Int]) {
    var numbersByID: [String: Int] = [:]
    var ordered: [MarkdownFootnoteDefinition] = []
    var counter = 0

    for line in cleanedLines {
        let nsLine = line as NSString
        let matches = Self.footnoteReferenceRegex.matches(
            in: line,
            range: NSRange(location: 0, length: nsLine.length)
        )
        for match in matches {
            let id = nsLine.substring(with: match.range(at: 1))
            guard definitions[id] != nil, numbersByID[id] == nil else { continue }
            counter += 1
            numbersByID[id] = counter
            ordered.append(MarkdownFootnoteDefinition(
                id: id,
                number: counter,
                paragraphs: definitions[id] ?? []
            ))
        }
    }
    return (ordered, numbersByID)
}
```

- [ ] **Step 6: Replace references in cleaned lines**

Add:

```swift
private static let superscriptDigits: [Character: Character] = [
    "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
    "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
]

private func replaceFootnoteReferences(
    in lines: [String],
    numbersByID: [String: Int]
) -> [String] {
    return lines.map { line -> String in
        let nsLine = line as NSString
        let matches = Self.footnoteReferenceRegex.matches(
            in: line,
            range: NSRange(location: 0, length: nsLine.length)
        )
        guard !matches.isEmpty else { return line }

        var result = ""
        var cursor = 0
        for match in matches {
            let id = nsLine.substring(with: match.range(at: 1))
            result += nsLine.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if let n = numbersByID[id] {
                result += String(String(n).compactMap { Self.superscriptDigits[$0] })
            } else {
                // Undefined — leave literal.
                result += nsLine.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        result += nsLine.substring(from: cursor)
        return result
    }
}
```

- [ ] **Step 7: Wire the pre-passes into `parseBlocks`**

In `parseBlocks` (around line 216), replace the existing line-splitting prelude:

```swift
private func parseBlocks(in source: String) throws -> [MarkdownBlock] {
    let normalizedSource = normalizeLineEndings(in: source)
    let rawLines = normalizedSource.components(separatedBy: .newlines)

    // Footnote pre-pass: extract definitions, resolve order, rewrite references.
    let extracted = extractFootnoteDefinitions(from: rawLines)
    let resolved = resolveFootnoteOrder(cleanedLines: extracted.cleaned, definitions: extracted.definitions)
    let lines = replaceFootnoteReferences(in: extracted.cleaned, numbersByID: resolved.numbersByID)

    var blocks: [MarkdownBlock] = []
    var index = 0

    // … existing front matter + main loop unchanged …

    // After the main loop finishes:
    if !resolved.ordered.isEmpty {
        blocks.append(.footnotesSection(resolved.ordered))
    }

    return blocks
}
```

- [ ] **Step 8: Render the footnotes section**

In `append(_:to:baseURL:)`, add:

```swift
        case .footnotesSection(let defs):
            appendFootnotesSection(defs, baseURL: baseURL, to: output)
```

And the helper near `appendTable`:

```swift
private func appendFootnotesSection(
    _ defs: [MarkdownFootnoteDefinition],
    baseURL: URL,
    to output: NSMutableAttributedString
) {
    let scale = settings.textSizeLevel.scaleFactor

    // Title rule.
    output.append(NSAttributedString(string: "\n", attributes: paragraphAttributes()))
    let title = NSMutableAttributedString(string: "Footnotes", attributes: [
        .font: settings.fontFamily.font(ofSize: 13 * scale, weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: bodyParagraphStyle()
    ])
    output.append(title)
    output.append(NSAttributedString(string: "\n", attributes: paragraphAttributes()))

    for (i, def) in defs.enumerated() {
        let body = def.paragraphs.joined(separator: "\n\n")
        let prefix = "\(def.number). "
        appendInlineMarkdown(prefix + body, baseURL: baseURL, baseAttributes: paragraphAttributes(), to: output)
        if i < defs.count - 1 {
            output.append(NSAttributedString(string: "\n\n", attributes: paragraphAttributes()))
        }
    }
}
```

- [ ] **Step 9: Add `.footnotesSection` to `instrumentationName`**

```swift
        case .footnotesSection: return "footnotesSection"
```

- [ ] **Step 10: Run tests to verify**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderInlineFootnoteReferenceIsSuperscript -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderUndefinedFootnoteReferenceRendersLiteral -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderRendersFootnoteSectionInDocumentOrder
```

Expected: 3 tests PASS.

- [ ] **Step 11: Fixture and visual check**

Create `Fixtures/Pluk-Parity/footnotes.md`:

```markdown
# Footnotes

Body text references the first note[^1] and the second[^second].

A line with no footnote.

References can include[^undefined] undefined ones too.

[^second]: Second-note body. Multi-word.

[^1]: First note body. Has **inline** markdown.

    Continuation paragraph (4-space indent) for the first note.
```

Run: `qlmanage -p Fixtures/Pluk-Parity/footnotes.md`.

Expected: superscripts in body, undefined `[^undefined]` literal, footnotes section at bottom in order 1, 2.

- [ ] **Step 12: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift Fixtures/Pluk-Parity/footnotes.md
git commit -m "feat: parse markdown footnote references and render a numbered footnotes section"
```

---

### Task 3: Table column alignment

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`
- Create: `Fixtures/Pluk-Parity/aligned-table.md`

- [ ] **Step 1: Add the alignment enum and extend `MarkdownTable`**

Replace the current `MarkdownTable` struct (line 46-49):

```swift
struct MarkdownTable: Sendable {
    enum ColumnAlignment: Sendable {
        case natural, left, center, right
    }
    let headers: [String]
    let alignments: [ColumnAlignment]
    let rows: [[String]]
}
```

- [ ] **Step 2: Failing test**

```swift
func testRenderTableRespectsColumnAlignment() throws {
    let payload = try renderDocument(
        """
        | Left | Center | Right |
        | :--- | :----: | ----: |
        | a    | b      | c     |
        """
    ).payload

    let rendered = renderedTextStorage(from: payload.attributedContent)
    let nsString = rendered.string as NSString

    let leftRange = nsString.range(of: "a")
    let centerRange = nsString.range(of: "b")
    let rightRange = nsString.range(of: "c")

    let leftStyle = rendered.attribute(.paragraphStyle, at: leftRange.location, effectiveRange: nil) as? NSParagraphStyle
    let centerStyle = rendered.attribute(.paragraphStyle, at: centerRange.location, effectiveRange: nil) as? NSParagraphStyle
    let rightStyle = rendered.attribute(.paragraphStyle, at: rightRange.location, effectiveRange: nil) as? NSParagraphStyle

    XCTAssertEqual(leftStyle?.alignment, .left)
    XCTAssertEqual(centerStyle?.alignment, .center)
    XCTAssertEqual(rightStyle?.alignment, .right)
}

func testRenderTableWithoutAlignmentMarkersStaysNatural() throws {
    let payload = try renderDocument(
        """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """
    ).payload
    let rendered = renderedTextStorage(from: payload.attributedContent)
    let style = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    XCTAssertEqual(style?.alignment, .natural)
}
```

- [ ] **Step 3: Run, confirm failure**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderTableRespectsColumnAlignment
```

Expected: FAIL (alignment field doesn't exist; everything is `.natural`).

- [ ] **Step 4: Parse alignment from separator row**

Add a helper near `isTableSeparatorLine` (around line 531):

```swift
private func tableColumnAlignments(from separatorLine: String) -> [MarkdownTable.ColumnAlignment] {
    return tableCells(from: separatorLine).map { cell -> MarkdownTable.ColumnAlignment in
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        let startsWithColon = trimmed.hasPrefix(":")
        let endsWithColon = trimmed.hasSuffix(":")
        switch (startsWithColon, endsWithColon) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        case (false, false): return .natural
        }
    }
}
```

- [ ] **Step 5: Pass alignments through `parseTableBlock`**

Replace the body of `parseTableBlock` (around line 491):

```swift
private func parseTableBlock(from lines: [String], startingAt index: Int) throws -> (table: MarkdownTable, nextIndex: Int)? {
    guard isTableLine(lines[index]) else { return nil }
    guard index + 1 < lines.count, isTableSeparatorLine(lines[index + 1]) else { return nil }

    let headers = tableCells(from: lines[index])
    var alignments = tableColumnAlignments(from: lines[index + 1])
    // Pad to header count.
    while alignments.count < headers.count { alignments.append(.natural) }
    if alignments.count > headers.count { alignments = Array(alignments.prefix(headers.count)) }

    var cursor = index + 2
    var rows: [[String]] = []

    while cursor < lines.count, isTableLine(lines[cursor]) {
        try throwIfCancelled()
        var cells = tableCells(from: lines[cursor])
        while cells.count < headers.count { cells.append("") }
        if cells.count > headers.count { cells = Array(cells.prefix(headers.count)) }
        rows.append(cells)
        cursor += 1
    }

    return (MarkdownTable(headers: headers, alignments: alignments, rows: rows), cursor)
}
```

- [ ] **Step 6: Apply alignment in `appendTable`**

In `appendTable` (around line 860), modify `cellString` to take an alignment:

```swift
func cellString(_ text: String, row: Int, col: Int, isHeader: Bool, alignment: MarkdownTable.ColumnAlignment) -> NSAttributedString {
    let block = cellBlock(row: row, col: col, isHeader: isHeader)
    let style = NSMutableParagraphStyle()
    style.textBlocks = [block]
    switch alignment {
    case .left: style.alignment = .left
    case .center: style.alignment = .center
    case .right: style.alignment = .right
    case .natural: style.alignment = .natural
    }

    let attrs: [NSAttributedString.Key: Any] = [
        .font: isHeader ? boldFont : font,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: style
    ]

    return NSAttributedString(string: text + "\n", attributes: attrs)
}
```

And update the call sites in the same function:

```swift
    // Header row.
    for (col, header) in table.headers.enumerated() {
        let alignment = col < table.alignments.count ? table.alignments[col] : .natural
        output.append(cellString(header, row: 0, col: col, isHeader: true, alignment: alignment))
    }

    // Data rows.
    for (rowIndex, row) in table.rows.enumerated() {
        for col in 0..<columnCount {
            let text = col < row.count ? row[col] : ""
            let alignment = col < table.alignments.count ? table.alignments[col] : .natural
            output.append(cellString(text, row: rowIndex + 1, col: col, isHeader: false, alignment: alignment))
        }
    }
```

- [ ] **Step 7: Fix any other `MarkdownTable(...)` initializer call sites**

Search for `MarkdownTable(` in the codebase:

```bash
grep -rn "MarkdownTable(" MarkdownRendering/
```

Update every other initialization to include the new `alignments` parameter (likely just test fixtures and the parser itself).

- [ ] **Step 8: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderTableRespectsColumnAlignment -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderTableWithoutAlignmentMarkersStaysNatural
```

Expected: 2 tests PASS. Re-run the whole `MarkdownRenderingTests` scheme to catch fallout in other table tests.

- [ ] **Step 9: Fixture and visual check**

Create `Fixtures/Pluk-Parity/aligned-table.md`:

```markdown
# Aligned table

| Left aligned | Centered | Right aligned | Default |
| :----------- | :------: | ------------: | ------- |
| short        | x        | 1             | a       |
| longer text  | yyy      | 100           | b       |
| even longer  | zzzzz    | 10000         | c       |
```

```bash
qlmanage -p Fixtures/Pluk-Parity/aligned-table.md
```

- [ ] **Step 10: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift Fixtures/Pluk-Parity/aligned-table.md
git commit -m "feat: honor GFM column alignment markers in tables"
```

---

### Task 4: Indented code blocks

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Failing test**

```swift
func testRenderIndentedCodeBlock() throws {
    let payload = try renderDocument(
        """
        Intro text.

            let x = 1
            let y = 2

        Outro text.
        """
    ).payload

    let s = payload.attributedContent.string
    XCTAssertTrue(s.contains("let x = 1"), "code line one")
    XCTAssertTrue(s.contains("let y = 2"), "code line two")
    XCTAssertTrue(s.contains("Intro text."))
    XCTAssertTrue(s.contains("Outro text."))

    // The code block should be a single code block — paragraph break before/after.
    let rendered = renderedTextStorage(from: payload.attributedContent)
    let codeRange = (rendered.string as NSString).range(of: "let x = 1")
    let font = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
    XCTAssertTrue(font?.isFixedPitch ?? false, "indented block must use monospaced font")
}

func testRenderDoesNotTreatListContinuationAsIndentedCode() throws {
    let payload = try renderDocument(
        """
        - first

          second paragraph in same item
        """
    ).payload
    let s = payload.attributedContent.string
    XCTAssertTrue(s.contains("second paragraph in same item"))
    // List continuation is rendered as body text, not as monospaced code.
    let rendered = renderedTextStorage(from: payload.attributedContent)
    let range = (rendered.string as NSString).range(of: "second paragraph")
    let font = rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
    XCTAssertFalse(font?.isFixedPitch ?? false)
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderIndentedCodeBlock
```

Expected: FAIL (indented lines become an unhandled paragraph).

- [ ] **Step 3: Add the indented-code parser**

In `MarkdownDocumentRenderer.swift`, add near `parseFencedCodeBlock`:

```swift
private func parseIndentedCodeBlock(from lines: [String], startingAt index: Int) throws -> (text: String, nextIndex: Int)? {
    let line = lines[index]
    guard isIndentedCodeLine(line) else { return nil }

    var codeLines: [String] = [stripIndentForCode(line)]
    var cursor = index + 1
    var blankBuffer: [String] = []

    while cursor < lines.count {
        try throwIfCancelled()
        let candidate = lines[cursor]
        if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blankBuffer.append("")
            cursor += 1
            continue
        }
        if isIndentedCodeLine(candidate) {
            // Flush blanks as empty code lines.
            codeLines.append(contentsOf: blankBuffer)
            blankBuffer.removeAll()
            codeLines.append(stripIndentForCode(candidate))
            cursor += 1
            continue
        }
        break
    }

    return (codeLines.joined(separator: "\n"), cursor)
}

private func isIndentedCodeLine(_ line: String) -> Bool {
    if line.hasPrefix("\t") { return true }
    if line.hasPrefix("    ") { return true }
    return false
}

private func stripIndentForCode(_ line: String) -> String {
    if line.hasPrefix("\t") { return String(line.dropFirst()) }
    if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
    return line
}
```

- [ ] **Step 4: Wire into `parseBlocks`**

In `parseBlocks`, AFTER the fenced code check (around line 250) but BEFORE the heading check, add:

```swift
            if let indented = try parseIndentedCodeBlock(from: lines, startingAt: index) {
                blocks.append(.code(language: nil, text: indented.text))
                index = indented.nextIndex
                continue
            }
```

Order matters: list parsers must not fire on `    foo` when it's *after* a list bullet — but list parsing already consumes its own continuations before returning control to the top of the loop. Since `parseBlocks` only re-enters at fresh block starts after `index` is bumped, an indented run that follows a list will already be past list scope.

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
```

Expected: both new tests PASS, no regression in the existing list-continuation test.

- [ ] **Step 6: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: parse 4-space-indented blocks as code"
```

---

### Task 5: Reference-style links — verify and patch

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift` (if patch needed)
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

Apple's `AttributedString(markdown:)` accepts reference links *only* when the entire document is parsed in one go. We parse paragraph-by-paragraph (`.inlineOnlyPreservingWhitespace`), which **does not** resolve them. We have to extract definitions ourselves and inline them.

- [ ] **Step 1: Failing test**

```swift
func testRenderResolvesReferenceStyleLinks() throws {
    let payload = try renderDocument(
        """
        See [Apple][site] for details.

        [site]: https://apple.com "Apple Inc."
        """
    ).payload

    let rendered = renderedTextStorage(from: payload.attributedContent)
    let linkRange = (rendered.string as NSString).range(of: "Apple")
    let link = rendered.attribute(.link, at: linkRange.location, effectiveRange: nil)

    XCTAssertNotNil(link, "Apple should be a resolved link")
    let url = (link as? URL) ?? URL(string: link as? String ?? "")
    XCTAssertEqual(url?.absoluteString, "https://apple.com")
    XCTAssertFalse(payload.attributedContent.string.contains("[site]:"), "definition line should be hidden")
}

func testRenderLeavesUnresolvedReferenceLiteral() throws {
    let payload = try renderDocument("See [missing][nope].").payload
    XCTAssertTrue(payload.attributedContent.string.contains("[missing][nope]"))
}
```

- [ ] **Step 2: Run, confirm failure**

- [ ] **Step 3: Add the definition extraction pre-pass**

Add near the footnote pre-pass:

```swift
private static let linkDefinitionRegex: NSRegularExpression = {
    // [label]: url ["optional title"|'optional title'|(optional title)]
    try! NSRegularExpression(pattern: #"^\s{0,3}\[([^\]]+)\]:\s+(\S+)(?:\s+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?\s*$"#)
}()

private func extractLinkDefinitions(from lines: [String]) -> (cleaned: [String], definitions: [String: String]) {
    var cleaned: [String] = []
    var definitions: [String: String] = [:]
    for line in lines {
        let nsLine = line as NSString
        if let match = Self.linkDefinitionRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
            let label = nsLine.substring(with: match.range(at: 1)).lowercased()
            let url = nsLine.substring(with: match.range(at: 2))
            if definitions[label] == nil { definitions[label] = url }
            continue
        }
        cleaned.append(line)
    }
    return (cleaned, definitions)
}

private static let referenceLinkRegex: NSRegularExpression = {
    // [text][label]   — collapsed form [text][] handled as [text][text]
    try! NSRegularExpression(pattern: #"\[([^\]]+)\]\[([^\]]*)\]"#)
}()

private func resolveReferenceLinks(in lines: [String], definitions: [String: String]) -> [String] {
    return lines.map { line -> String in
        let nsLine = line as NSString
        let matches = Self.referenceLinkRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        guard !matches.isEmpty else { return line }
        var result = ""
        var cursor = 0
        for match in matches {
            let text = nsLine.substring(with: match.range(at: 1))
            let rawLabel = nsLine.substring(with: match.range(at: 2))
            let label = (rawLabel.isEmpty ? text : rawLabel).lowercased()
            result += nsLine.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if let url = definitions[label] {
                result += "[\(text)](\(url))"
            } else {
                result += nsLine.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        result += nsLine.substring(from: cursor)
        return result
    }
}
```

- [ ] **Step 4: Wire into `parseBlocks`**

In `parseBlocks`, after the footnote pre-pass but before line iteration begins:

```swift
    let linkExtracted = extractLinkDefinitions(from: extracted.cleaned)
    let resolvedLines = resolveReferenceLinks(in: linkExtracted.cleaned, definitions: linkExtracted.definitions)
    // Then run the footnote-reference replacement against `resolvedLines`:
    let lines = replaceFootnoteReferences(in: resolvedLines, numbersByID: resolved.numbersByID)
```

(Reorder so link-def extraction is before footnote-reference numbering, since neither depends on the other.)

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderResolvesReferenceStyleLinks -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderLeavesUnresolvedReferenceLiteral
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: resolve reference-style links by inlining definitions"
```

---

### Task 6: TOML front matter (`+++ ... +++`)

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`
- Create: `Fixtures/Pluk-Parity/toml-frontmatter.md`

- [ ] **Step 1: Failing test**

```swift
func testRenderRecognizesTOMLFrontMatter() throws {
    let payload = try renderDocument(
        """
        +++
        title = "Hello"
        +++

        # Body
        """
    ).payload

    let s = payload.attributedContent.string
    XCTAssertTrue(s.contains(#"title = "Hello""#), "TOML body rendered")
    XCTAssertTrue(s.contains("Body"))
    XCTAssertFalse(s.contains("+++"), "TOML fence should be hidden in output")
}
```

- [ ] **Step 2: Confirm failure**

- [ ] **Step 3: Extend front-matter parsing**

In `parseBlocks` (around line 222-236), replace the YAML-only block with:

```swift
    // Parse YAML or TOML front matter before main loop.
    if index < lines.count {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed == "---" || trimmed == "+++" {
            let delimiter = trimmed
            var fmLines: [String] = []
            var cursor = index + 1
            while cursor < lines.count {
                let line = lines[cursor]
                if line.trimmingCharacters(in: .whitespaces) == delimiter {
                    blocks.append(.frontMatter(fmLines.joined(separator: "\n")))
                    index = cursor + 1
                    break
                }
                fmLines.append(line)
                cursor += 1
            }
        }
    }
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderRecognizesTOMLFrontMatter
```

Expected: PASS. Also re-run any existing YAML front-matter test to confirm no regression.

- [ ] **Step 5: Fixture and visual check**

Create `Fixtures/Pluk-Parity/toml-frontmatter.md`:

```markdown
+++
title = "TOML demo"
date = 2026-05-23
draft = false
tags = ["sample", "markdown"]
+++

# Hugo-style document

This document uses TOML front matter common in Hugo/Zola sites.
```

```bash
qlmanage -p Fixtures/Pluk-Parity/toml-frontmatter.md
```

- [ ] **Step 6: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift Fixtures/Pluk-Parity/toml-frontmatter.md
git commit -m "feat: recognize TOML front matter delimited by +++"
```

---

### Task 7: Code-fence info-string parsing

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Failing test**

```swift
func testRenderTreatsOnlyFirstWordAsCodeFenceLanguage() throws {
    let payload = try renderDocument(
        """
        ```swift title="example.swift"
        let x = 1
        ```
        """
    ).payload

    let rendered = renderedTextStorage(from: payload.attributedContent)
    let codeRange = (rendered.string as NSString).range(of: "let x = 1")
    XCTAssertNotEqual(codeRange.location, NSNotFound)

    // Swift highlighting tints `let` system-pink.
    let letRange = (rendered.string as NSString).range(of: "let")
    let color = rendered.attribute(.foregroundColor, at: letRange.location, effectiveRange: nil) as? NSColor
    XCTAssertEqual(color, NSColor.systemPink, "swift keyword should be highlighted — proving language=swift")
}

func testRenderTreatsMermaidWithAttributesAsMermaid() throws {
    let payload = try renderDocument(
        """
        ```mermaid {theme=dark}
        graph TD; A-->B;
        ```
        """
    ).payload

    XCTAssertTrue(
        payload.attributedContent.string.contains("Mermaid Diagram"),
        "the 📊 Mermaid Diagram label should fire — proving language=mermaid"
    )
}
```

- [ ] **Step 2: Confirm failure**

- [ ] **Step 3: Patch `parseFencedCodeBlock`**

Replace the language-extraction block (line 310-312) with:

```swift
    let fenceTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
    let infoString = String(fenceTrimmed.drop { $0 == "`" }.trimmingCharacters(in: .whitespaces))
    // Only the first whitespace-delimited token is the language; the rest is metadata.
    let language: String? = {
        guard !infoString.isEmpty else { return nil }
        let firstToken = infoString.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return firstToken.isEmpty ? nil : firstToken.lowercased()
    }()
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderTreatsOnlyFirstWordAsCodeFenceLanguage -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderTreatsMermaidWithAttributesAsMermaid
```

Expected: PASS. Re-run the full renderer suite to make sure no test was depending on the old whole-string behavior.

- [ ] **Step 5: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "fix: extract only the first token of a code fence info string as the language"
```

---

### Task 8: Smart-dashes setting flag

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownRenderSettings.swift`
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`

- [ ] **Step 1: Read the current settings type**

```bash
grep -n "smartDashes\|let \|var " MarkdownRendering/Sources/MarkdownRenderSettings.swift | head -40
```

This identifies where to add a new stored property. The class is `MarkdownRenderSettings`.

- [ ] **Step 2: Add the flag (default `true`)**

In `MarkdownRenderSettings.swift`, add a stored property:

```swift
public let smartDashes: Bool
```

Update the initializer and `default` to include it:

```swift
public init(
    // ...existing params...
    smartDashes: Bool = true
) {
    // ...
    self.smartDashes = smartDashes
}

public static var `default`: MarkdownRenderSettings {
    MarkdownRenderSettings(smartDashes: true /*…with other defaults */)
}
```

(Adapt to the actual signature in your tree.)

- [ ] **Step 3: Persist via UserDefaults in `MarkdownSettingsStore.swift`**

Add JSON key `"smartDashes": Bool` to the coding. Default `true` when missing.

- [ ] **Step 4: Failing test**

```swift
func testRenderDisablesSmartDashesWhenSettingOff() throws {
    let settings = MarkdownRenderSettings(/* …, */ smartDashes: false)
    let renderer = MarkdownDocumentRenderer(settings: settings)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dashes-\(UUID().uuidString).md")
    try "Hello---world.".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let payload = try renderer.render(fileAt: url)
    XCTAssertTrue(payload.attributedContent.string.contains("---"), "literal triple-dash retained when smart dashes disabled")
    XCTAssertFalse(payload.attributedContent.string.contains("\u{2014}"))
}
```

- [ ] **Step 5: Gate the dash replacement on the setting**

In `MarkdownDocumentRenderer.swift`, inside `inlineMarkdownAttributedString` (around line 686), change:

```swift
let shouldReplaceDashes = containsDashReplacementCandidate(text)
```

to:

```swift
let shouldReplaceDashes = settings.smartDashes && containsDashReplacementCandidate(text)
```

- [ ] **Step 6: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderDisablesSmartDashesWhenSettingOff
```

Expected: PASS. Re-run the full suite — existing dash tests must still pass with the default-on behavior.

- [ ] **Step 7: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownRenderSettings.swift MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Sources/MarkdownSettingsStore.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift
git commit -m "feat: gate smart-dash conversion behind a render setting (default on)"
```

---

### Task 9: Expanded UTI / file-extension support

**Files:**
- Modify: `MarkdownQuickLookPreviewExtension/Info.plist`
- Modify: `MarkdownQuickLookThumbnailExtension/Info.plist`
- Modify: `MarkdownQuickLookApp/Info.plist`

No tests — this is a manifest change. Verification is "extension fires on the new UTI."

- [ ] **Step 1: Extend the preview extension's UTI list**

Open `MarkdownQuickLookPreviewExtension/Info.plist` and replace the `QLSupportedContentTypes` array (currently only `net.daringfireball.markdown`):

```xml
                <key>QLSupportedContentTypes</key>
                <array>
                    <string>net.daringfireball.markdown</string>
                    <string>public.markdown</string>
                    <string>net.ia.markdown</string>
                    <string>com.unknown.md</string>
                </array>
```

- [ ] **Step 2: Same change in the thumbnail extension**

`MarkdownQuickLookThumbnailExtension/Info.plist` → same expansion in its `QLSupportedContentTypes`.

- [ ] **Step 3: Same change in the app's document types**

In `MarkdownQuickLookApp/Info.plist`, replace the `LSItemContentTypes` array under `CFBundleDocumentTypes` with the same expanded list.

- [ ] **Step 4: Build and visually verify**

Generate the project, build the app, install. Then:

```bash
# Save a file with iA Writer's UTI (or any non-DF markdown)
echo "# hi" > /tmp/test.md
# Set the UTI to public.markdown explicitly (macOS tool)
xattr -w com.apple.metadata:kMDItemContentType public.markdown /tmp/test.md
qlmanage -p /tmp/test.md
```

Expected: preview fires for `public.markdown`. Repeat for `net.ia.markdown` and `com.unknown.md` if you have files to test with.

- [ ] **Step 5: Commit**

```bash
git add MarkdownQuickLookPreviewExtension/Info.plist MarkdownQuickLookThumbnailExtension/Info.plist MarkdownQuickLookApp/Info.plist
git commit -m "feat: declare additional markdown UTIs across preview, thumbnail, and app targets"
```

---

### Task 10: RTL paragraph direction

**Files:**
- Modify: `MarkdownRendering/Sources/MarkdownDocumentRenderer.swift`
- Modify: `MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift`
- Create: `Fixtures/Pluk-Parity/rtl.md`

- [ ] **Step 1: Failing test**

```swift
func testRenderAppliesRightToLeftDirectionForArabicParagraph() throws {
    let payload = try renderDocument(
        """
        مرحبا بالعالم. هذه فقرة باللغة العربية.

        English paragraph after.
        """
    ).payload

    let rendered = renderedTextStorage(from: payload.attributedContent)
    let arabicRange = (rendered.string as NSString).range(of: "مرحبا")
    let englishRange = (rendered.string as NSString).range(of: "English")

    let arabicStyle = rendered.attribute(.paragraphStyle, at: arabicRange.location, effectiveRange: nil) as? NSParagraphStyle
    let englishStyle = rendered.attribute(.paragraphStyle, at: englishRange.location, effectiveRange: nil) as? NSParagraphStyle

    XCTAssertEqual(arabicStyle?.baseWritingDirection, .rightToLeft)
    XCTAssertNotEqual(englishStyle?.baseWritingDirection, .rightToLeft)
}
```

- [ ] **Step 2: Confirm failure**

- [ ] **Step 3: Add the RTL detector**

Add to `MarkdownDocumentRenderer.swift`:

```swift
private func paragraphIsRTL(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        // Arabic, Hebrew, Syriac, Thaana, NKo, Samaritan, Mandaic, plus their
        // Supplement / Extended / Presentation Forms.
        let direction = Unicode.Scalar.Properties.bidiClass
        let props = scalar.properties
        switch props.bidiClass(direction) ?? .leftToRight {
        case .rightToLeft, .rightToLeftArabic:
            return true
        case .leftToRight:
            return false
        default:
            continue
        }
    }
    return false
}
```

**If** `Unicode.Scalar.Properties.bidiClass(_:)` is not available in your Swift / macOS SDK (it's relatively new — `macOS 13+`), fall back to a Unicode-block check:

```swift
private func paragraphIsRTL(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        let v = scalar.value
        // Hebrew, Arabic (incl. Supplement, Presentation Forms A/B).
        if (0x0590...0x05FF).contains(v) ||
           (0x0600...0x06FF).contains(v) ||
           (0x0750...0x077F).contains(v) ||
           (0xFB50...0xFDFF).contains(v) ||
           (0xFE70...0xFEFF).contains(v) {
            return true
        }
        // Latin / Greek / Cyrillic / Han etc. — first strong LTR wins.
        if (0x0041...0x007A).contains(v) ||
           (0x00C0...0x024F).contains(v) ||
           (0x4E00...0x9FFF).contains(v) {
            return false
        }
    }
    return false
}
```

Use whichever compiles. Land the simpler block-check version if the API check is uncertain.

- [ ] **Step 4: Apply per-paragraph direction in `appendInlineMarkdown`**

In `MarkdownDocumentRenderer.swift`, modify `inlineMarkdownAttributedString` to apply direction at the end:

```swift
// After all other attribute application, before `return attributed`:
if paragraphIsRTL(text) {
    let fullRange = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
        let base = (value as? NSParagraphStyle) ?? bodyParagraphStyle()
        let mutable = base.mutableCopy() as! NSMutableParagraphStyle
        mutable.baseWritingDirection = .rightToLeft
        attributed.addAttribute(.paragraphStyle, value: mutable as NSParagraphStyle, range: range)
    }
}
```

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS' -only-testing:MarkdownRenderingTests/MarkdownDocumentRendererTests/testRenderAppliesRightToLeftDirectionForArabicParagraph
```

Expected: PASS.

- [ ] **Step 6: Fixture and visual check**

Create `Fixtures/Pluk-Parity/rtl.md`:

```markdown
# RTL paragraph direction

مرحبا بالعالم. هذه فقرة باللغة العربية تختبر اتجاه النص.

English paragraph between two RTL paragraphs.

שלום עולם. זוהי פסקה בעברית.
```

```bash
qlmanage -p Fixtures/Pluk-Parity/rtl.md
```

- [ ] **Step 7: Commit**

```bash
git add MarkdownRendering/Sources/MarkdownDocumentRenderer.swift MarkdownRendering/Tests/MarkdownDocumentRendererTests.swift Fixtures/Pluk-Parity/rtl.md
git commit -m "feat: detect RTL paragraphs and apply right-to-left base writing direction"
```

---

## End-of-phase verification

- [ ] **Run the full suite**

```bash
xcodegen generate
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownRenderingTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookPreviewExtensionTests -destination 'platform=macOS'
xcodebuild test -project MarkdownQuickLook.xcodeproj -scheme MarkdownQuickLookAppTests -destination 'platform=macOS'
```

Expected: all green.

- [ ] **Cycle through fixtures with `qlmanage`**

```bash
for f in Fixtures/Pluk-Parity/*.md; do qlmanage -p "$f"; done
```

Manually confirm each renders as the corresponding feature description.

- [ ] **Performance regression check**

Re-run the existing perf fixtures (`Fixtures/Performance/*.md`) — none of the parser additions should add measurable cost. The footnote and link pre-passes are linear in the line count and run before the main loop; they should not regress the published baseline in `MarkdownPerformanceInstrumentation`.

```bash
./Scripts/perf-baseline.sh 2>/dev/null || echo "no perf script — measure manually via instrumentation logs"
```

## Out-of-scope reminders

- Math (`$x$`, `$$x$$`, ```` ```math ````) — Phase 4.
- Mermaid rendering — Phase 4.
- Code-block copy button — Phase 2.
- Anything that ships visible behavior outside the parser/renderer — see other phase plans.
