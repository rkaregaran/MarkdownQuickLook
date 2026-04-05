import AppKit
import Foundation

public struct MarkdownRenderPayload {
    public let title: String
    public let attributedContent: NSAttributedString

    public init(title: String, attributedContent: NSAttributedString) {
        self.title = title
        self.attributedContent = attributedContent
    }
}

public enum MarkdownDocumentRendererError: Error, Equatable, LocalizedError, Sendable {
    case unreadableFile(URL)
    case emptyDocument(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let url):
            return "Quick Look could not read \(url.lastPathComponent)."
        case .emptyDocument(let url):
            return "\(url.lastPathComponent) is empty."
        }
    }
}

enum MarkdownBlock: Sendable {
    case frontMatter(String)
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote([String])
    case list([MarkdownListItem])
    case code(language: String?, text: String)
    case table(MarkdownTable)
    case horizontalRule
    case image(alt: String, path: String)
}

struct MarkdownTable: Sendable {
    let headers: [String]
    let rows: [[String]]
}

struct MarkdownListItem: Sendable {
    let index: Int?
    let paragraphs: [String]
    let children: [MarkdownListItem]
}

public struct MarkdownPreparedDocument: Sendable {
    public let title: String
    let baseURL: URL
    let blocks: [MarkdownBlock]
}

public final class MarkdownDocumentRenderer {
    private let settings: MarkdownRenderSettings

    public init(settings: MarkdownRenderSettings = .default) {
        self.settings = settings
    }

    public func prepareDocument(fileAt url: URL) throws -> MarkdownPreparedDocument {
        try throwIfCancelled()
        let source: String

        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MarkdownDocumentRendererError.unreadableFile(url)
        }

        try throwIfCancelled()

        guard source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MarkdownDocumentRendererError.emptyDocument(url)
        }

        return MarkdownPreparedDocument(
            title: url.lastPathComponent,
            baseURL: url.deletingLastPathComponent(),
            blocks: try parseBlocks(in: source)
        )
    }

    @MainActor
    public func render(document: MarkdownPreparedDocument) -> MarkdownRenderPayload {
        let formatted = NSMutableAttributedString()

        for (index, block) in document.blocks.enumerated() {
            append(block, to: formatted, baseURL: document.baseURL)

            if index < document.blocks.count - 1 {
                formatted.append(NSAttributedString(string: "\n\n"))
            }
        }

        return MarkdownRenderPayload(
            title: document.title,
            attributedContent: NSAttributedString(attributedString: formatted)
        )
    }

    @MainActor
    public func render(
        document: MarkdownPreparedDocument,
        shouldContinue: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> MarkdownRenderPayload {
        let formatted = NSMutableAttributedString()

        for (index, block) in document.blocks.enumerated() {
            try ensureRenderingCanContinue(shouldContinue)
            append(block, to: formatted, baseURL: document.baseURL)

            if index < document.blocks.count - 1 {
                formatted.append(NSAttributedString(string: "\n\n"))
                await Task.yield()
            }
        }

        try ensureRenderingCanContinue(shouldContinue)

        return MarkdownRenderPayload(
            title: document.title,
            attributedContent: NSAttributedString(attributedString: formatted)
        )
    }

    @MainActor
    public func render(fileAt url: URL) throws -> MarkdownRenderPayload {
        try render(document: prepareDocument(fileAt: url))
    }

    private func parseBlocks(in source: String) throws -> [MarkdownBlock] {
        let normalizedSource = normalizeLineEndings(in: source)
        let lines = normalizedSource.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

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
        }

        while index < lines.count {
            try throwIfCancelled()

            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
                continue
            }

            if let codeBlock = try parseFencedCodeBlock(from: lines, startingAt: index) {
                blocks.append(.code(language: codeBlock.language, text: codeBlock.text))
                index = codeBlock.nextIndex
                continue
            }

            if let heading = heading(from: lines[index]) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isHorizontalRule(lines[index]) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            if let quote = try parseQuoteBlock(from: lines, startingAt: index) {
                blocks.append(.quote(quote.paragraphs))
                index = quote.nextIndex
                continue
            }

            if let list = try parseListBlock(from: lines, startingAt: index) {
                blocks.append(.list(list.items))
                index = list.nextIndex
                continue
            }

            if let orderedList = try parseOrderedListBlock(from: lines, startingAt: index) {
                blocks.append(.list(orderedList.items))
                index = orderedList.nextIndex
                continue
            }

            if let table = try parseTableBlock(from: lines, startingAt: index) {
                blocks.append(.table(table.table))
                index = table.nextIndex
                continue
            }

            if let img = imageReference(from: lines[index]) {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if trimmed == "![\(img.alt)](\(img.path))" {
                    blocks.append(.image(alt: img.alt, path: img.path))
                    index += 1
                    continue
                }
            }

            let paragraph = try parseParagraph(from: lines, startingAt: index)
            blocks.append(.paragraph(paragraph.text))
            index = paragraph.nextIndex
        }

        return blocks
    }

    private func parseFencedCodeBlock(from lines: [String], startingAt index: Int) throws -> (language: String?, text: String, nextIndex: Int)? {
        guard isFenceLine(lines[index]) else {
            return nil
        }

        let fenceTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let langHint = String(fenceTrimmed.drop { $0 == "`" }.trimmingCharacters(in: .whitespaces))
        let language = langHint.isEmpty ? nil : langHint.lowercased()

        var codeLines: [String] = []
        var cursor = index + 1

        while cursor < lines.count, isFenceLine(lines[cursor]) == false {
            try throwIfCancelled()
            codeLines.append(lines[cursor])
            cursor += 1
        }

        if cursor < lines.count, isFenceLine(lines[cursor]) {
            cursor += 1
        }

        return (language, codeLines.joined(separator: "\n"), cursor)
    }

    private func parseQuoteBlock(from lines: [String], startingAt index: Int) throws -> (paragraphs: [String], nextIndex: Int)? {
        guard isQuoteLine(lines[index]) else {
            return nil
        }

        var paragraphs: [String] = []
        var currentParagraphLines: [String] = []
        var cursor = index

        while cursor < lines.count, isQuoteLine(lines[cursor]) {
            try throwIfCancelled()
            let content = quoteContent(from: lines[cursor])

            if content.isEmpty {
                if currentParagraphLines.isEmpty == false {
                    paragraphs.append(currentParagraphLines.joined(separator: " "))
                    currentParagraphLines.removeAll()
                }
            } else {
                currentParagraphLines.append(content)
            }

            cursor += 1
        }

        if currentParagraphLines.isEmpty == false {
            paragraphs.append(currentParagraphLines.joined(separator: " "))
        }

        return (paragraphs, cursor)
    }

    private func leadingSpaceCount(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private func parseListBlock(from lines: [String], startingAt index: Int) throws -> (items: [MarkdownListItem], nextIndex: Int)? {
        guard isBulletLine(lines[index]) else { return nil }

        let baseIndent = leadingSpaceCount(lines[index])
        var items: [MarkdownListItem] = []
        var cursor = index

        while cursor < lines.count {
            let line = lines[cursor]
            let lineIndent = leadingSpaceCount(line)
            guard isBulletLine(line), lineIndent == baseIndent else { break }

            try throwIfCancelled()
            let item = try parseListItemWithChildren(from: lines, startingAt: cursor, baseIndent: baseIndent, ordered: false)
            items.append(item.item)
            cursor = item.nextIndex
        }

        return items.isEmpty ? nil : (items, cursor)
    }

    private func parseOrderedListBlock(from lines: [String], startingAt index: Int) throws -> (items: [MarkdownListItem], nextIndex: Int)? {
        guard isOrderedListLine(lines[index]) else { return nil }

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
                if let next = nextNonBlankLineIndex(in: lines, startingAt: cursor + 1) {
                    let nextIndent = leadingSpaceCount(lines[next])
                    if nextIndent > baseIndent && (isBulletLine(lines[next]) || isOrderedListLine(lines[next])) {
                        cursor = next
                        continue
                    }
                    if nextIndent > baseIndent && !isBulletLine(lines[next]) && !isOrderedListLine(lines[next]) && !isBlockStart(lines[next]) {
                        // Continuation paragraph within the same item
                        let content = lines[next].trimmingCharacters(in: .whitespaces)
                        paragraphs.append(content)
                        cursor = next + 1
                        continue
                    }
                }
                break
            }

            let lineIndent = leadingSpaceCount(line)

            if lineIndent > baseIndent && isBulletLine(line) {
                if let nested = try parseListBlock(from: lines, startingAt: cursor) {
                    children.append(contentsOf: nested.items)
                    cursor = nested.nextIndex
                    continue
                }
            }

            if lineIndent > baseIndent && isOrderedListLine(line) {
                if let nested = try parseOrderedListBlock(from: lines, startingAt: cursor) {
                    children.append(contentsOf: nested.items)
                    cursor = nested.nextIndex
                    continue
                }
            }

            if isBulletLine(line) || isOrderedListLine(line) {
                break
            }

            if isBlockStart(line) {
                break
            }

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

    private func parseTableBlock(from lines: [String], startingAt index: Int) throws -> (table: MarkdownTable, nextIndex: Int)? {
        guard isTableLine(lines[index]) else { return nil }

        // Need at least a header row and a separator row.
        guard index + 1 < lines.count, isTableSeparatorLine(lines[index + 1]) else { return nil }

        let headers = tableCells(from: lines[index])
        var cursor = index + 2
        var rows: [[String]] = []

        while cursor < lines.count, isTableLine(lines[cursor]) {
            try throwIfCancelled()
            var cells = tableCells(from: lines[cursor])
            // Pad or truncate to match header count.
            while cells.count < headers.count { cells.append("") }
            if cells.count > headers.count { cells = Array(cells.prefix(headers.count)) }
            rows.append(cells)
            cursor += 1
        }

        return (MarkdownTable(headers: headers, rows: rows), cursor)
    }

    private func checkboxBullet(for text: String) -> (bullet: String, text: String) {
        if text.hasPrefix("[ ] ") {
            return ("⬜️", String(text.dropFirst(4)))
        }
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            return ("✅", String(text.dropFirst(4)))
        }
        return ("•", text)
    }

    private func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        // Must have at least two pipes (start and one delimiter).
        return trimmed.dropFirst().contains("|")
    }

    private func isTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        let stripped = trimmed.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty
    }

    private func tableCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("|") { trimmed = String(trimmed.dropLast()) }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func parseParagraph(from lines: [String], startingAt index: Int) throws -> (text: String, nextIndex: Int) {
        var parts = [lines[index].trimmingCharacters(in: .whitespaces)]
        var cursor = index + 1

        while cursor < lines.count {
            try throwIfCancelled()
            let line = lines[cursor]

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                break
            }

            if isBlockStart(line) {
                break
            }

            parts.append(line.trimmingCharacters(in: .whitespaces))
            cursor += 1
        }

        return (parts.joined(separator: " "), cursor)
    }

    private func append(_ block: MarkdownBlock, to output: NSMutableAttributedString, baseURL: URL) {
        switch block {
        case .heading(let level, let text):
            let attributed = inlineMarkdownAttributedString(
                from: text,
                baseURL: baseURL,
                baseAttributes: paragraphAttributes()
            )
            applyHeadingStyle(level: level, to: attributed)
            output.append(attributed)

        case .paragraph(let text):
            appendInlineMarkdown(text, baseURL: baseURL, baseAttributes: paragraphAttributes(), to: output)

        case .quote(let paragraphs):
            let text = paragraphs.joined(separator: "\n\n")
            appendInlineMarkdown(text, baseURL: baseURL, baseAttributes: quoteAttributes(), to: output)

        case .list(let items):
            appendListItems(items, depth: 0, baseURL: baseURL, to: output)

        case .code(let language, let text):
            appendCodeBlock(text, language: language, to: output)

        case .table(let table):
            appendTable(table, to: output)

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

        case .image(let alt, let path):
            appendImage(alt: alt, path: path, baseURL: baseURL, to: output)

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
        }
    }

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

            if !item.children.isEmpty {
                output.append(NSAttributedString(string: "\n"))
                appendListItems(item.children, depth: depth + 1, baseURL: baseURL, to: output)
            }

            if itemIndex < items.count - 1 {
                output.append(NSAttributedString(string: "\n"))
            }
        }
    }

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
        applyDashes(to: attributed, from: parsed)
        applyInlineCodeBackground(to: attributed, from: parsed)
        return attributed
    }

    private func applyStrikethrough(to attributed: NSMutableAttributedString, from source: AttributedString) {
        for run in source.runs {
            guard let intent = run.inlinePresentationIntent, intent.contains(.strikethrough) else { continue }
            let nsRange = NSRange(run.range, in: source)
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
        }
    }

    private func applyDashes(to attributed: NSMutableAttributedString, from source: AttributedString) {
        // Build a set of code ranges to skip.
        var codeRanges = IndexSet()
        for run in source.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                let nsRange = NSRange(run.range, in: source)
                codeRanges.insert(integersIn: nsRange.location..<(nsRange.location + nsRange.length))
            }
        }

        // Replace --- with em dash first (longer match first), then -- with en dash.
        let replacements: [(pattern: String, replacement: String)] = [
            ("---", "\u{2014}"),
            ("--", "\u{2013}")
        ]

        for (pattern, replacement) in replacements {
            var searchRange = NSRange(location: 0, length: attributed.length)
            while searchRange.location < attributed.length {
                let range = (attributed.string as NSString).range(of: pattern, range: searchRange)
                guard range.location != NSNotFound else { break }

                if !codeRanges.contains(integersIn: range.location..<(range.location + range.length)) {
                    attributed.replaceCharacters(in: range, with: replacement)
                    // Adjust code ranges after replacement.
                    let delta = replacement.count - range.length
                    var adjusted = IndexSet()
                    for r in codeRanges.rangeView {
                        if r.lowerBound > range.location {
                            adjusted.insert(integersIn: (r.lowerBound + delta)..<(r.upperBound + delta))
                        } else {
                            adjusted.insert(integersIn: r)
                        }
                    }
                    codeRanges = adjusted
                    searchRange = NSRange(location: range.location + replacement.count, length: attributed.length - range.location - replacement.count)
                } else {
                    searchRange = NSRange(location: range.location + range.length, length: attributed.length - range.location - range.length)
                }
            }
        }
    }

    private func applyInlineCodeBackground(to attributed: NSMutableAttributedString, from source: AttributedString) {
        let bgColor = NSColor(white: 0.5, alpha: 0.12)
        let scale = settings.textSizeLevel.scaleFactor
        let codeFont = NSFont.monospacedSystemFont(ofSize: 13 * scale, weight: .regular)

        for run in source.runs {
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else { continue }
            let nsRange = NSRange(run.range, in: source)
            attributed.addAttribute(.backgroundColor, value: bgColor, range: nsRange)
            attributed.addAttribute(.font, value: codeFont, range: nsRange)
        }
    }

    private func appendInlineMarkdown(
        _ text: String,
        baseURL: URL,
        baseAttributes: [NSAttributedString.Key: Any],
        to output: NSMutableAttributedString
    ) {
        output.append(inlineMarkdownAttributedString(from: text, baseURL: baseURL, baseAttributes: baseAttributes))
    }

    private func applyHeadingStyle(level: Int, to attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let headingColor = NSColor.labelColor
        let paragraph = bodyParagraphStyle()

        attributed.addAttribute(.foregroundColor, value: headingColor, range: fullRange)
        attributed.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)

        attributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let baseFont = (value as? NSFont) ?? headingBaseFont(for: level)
            let styledFont = headingFont(for: baseFont, level: level)
            attributed.addAttribute(.font, value: styledFont, range: range)
        }
    }

    private func headingBaseFont(for level: Int) -> NSFont {
        settings.fontFamily.font(ofSize: headingSize(for: level), weight: .semibold)
    }

    private func headingFont(for baseFont: NSFont, level: Int) -> NSFont {
        let size = headingSize(for: level)
        let sizedFont = baseFont.isFixedPitch ? NSFont.monospacedSystemFont(ofSize: size, weight: .semibold) : settings.fontFamily.font(ofSize: size, weight: .semibold)
        let manager = NSFontManager.shared
        var styledFont = sizedFont
        let traits = baseFont.fontDescriptor.symbolicTraits

        if traits.contains(.bold) {
            styledFont = manager.convert(styledFont, toHaveTrait: .boldFontMask)
        }

        if traits.contains(.italic) {
            styledFont = manager.convert(styledFont, toHaveTrait: .italicFontMask)
        }

        return styledFont
    }

    private func headingSize(for level: Int) -> CGFloat {
        let base: CGFloat
        switch level {
        case 1: base = 30
        case 2: base = 24
        case 3: base = 20
        default: base = 17
        }
        return base * settings.textSizeLevel.scaleFactor
    }

    private func appendTable(_ table: MarkdownTable, to output: NSMutableAttributedString) {
        let scale = settings.textSizeLevel.scaleFactor
        let font = NSFont.monospacedSystemFont(ofSize: 13 * scale, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 13 * scale, weight: .semibold)

        // Calculate column widths.
        var widths = table.headers.map { $0.count }
        for row in table.rows {
            for (col, cell) in row.enumerated() where col < widths.count {
                widths[col] = max(widths[col], cell.count)
            }
        }

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.textBackgroundColor,
            .paragraphStyle: codeParagraphStyle()
        ]
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.textBackgroundColor,
            .paragraphStyle: codeParagraphStyle()
        ]

        func padded(_ cells: [String]) -> String {
            cells.enumerated().map { i, cell in
                cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }.joined(separator: "  │  ")
        }

        // Header row.
        output.append(NSAttributedString(string: padded(table.headers), attributes: headerAttrs))

        // Separator.
        let separator = widths.map { String(repeating: "─", count: $0) }.joined(separator: "──┼──")
        output.append(NSAttributedString(string: "\n" + separator, attributes: baseAttrs))

        // Data rows.
        for row in table.rows {
            output.append(NSAttributedString(string: "\n" + padded(row), attributes: baseAttrs))
        }
    }

    private func appendCodeBlock(_ code: String, language: String?, to output: NSMutableAttributedString) {
        let scale = settings.textSizeLevel.scaleFactor
        let padding = 10 * scale
        let font = NSFont.monospacedSystemFont(ofSize: 13 * scale, weight: .regular)

        let textBlock = RoundedTextBlock()
        textBlock.backgroundColor = NSColor(white: 0.5, alpha: 0.12)
        textBlock.setContentWidth(100, type: .percentageValueType)
        for edge: NSRectEdge in [.minX, .maxX, .minY, .maxY] {
            textBlock.setWidth(padding, type: .absoluteValueType, for: .padding, edge: edge)
        }

        let codeStyle = NSMutableParagraphStyle()
        codeStyle.textBlocks = [textBlock]
        codeStyle.lineSpacing = 2 * scale

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: codeStyle
        ]

        let content: String
        if let label = codeBlockLabel(for: language) {
            content = label + "\n" + code
        } else {
            content = code
        }

        let highlighted = NSMutableAttributedString(string: content, attributes: baseAttributes)

        if let label = codeBlockLabel(for: language) {
            let labelRange = NSRange(location: 0, length: label.count)
            highlighted.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11 * scale, weight: .semibold), range: labelRange)
            highlighted.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: labelRange)
            let codeRange = NSRange(location: label.count + 1, length: code.count)
            let codeString = NSMutableAttributedString(attributedString: highlighted.attributedSubstring(from: codeRange))
            applySyntaxHighlighting(to: codeString, language: language, font: font)
            highlighted.replaceCharacters(in: codeRange, with: codeString)
        } else {
            applySyntaxHighlighting(to: highlighted, language: language, font: font)
        }

        output.append(highlighted)
    }

    private func codeBlockLabel(for language: String?) -> String? {
        switch language {
        case "mermaid": return "📊 Mermaid Diagram"
        case "math", "latex", "tex": return "📐 Math Expression"
        case "diagram": return "📊 Diagram"
        default: return nil
        }
    }

    private func appendImage(alt: String, path: String, baseURL: URL, to output: NSMutableAttributedString) {
        let scale = settings.textSizeLevel.scaleFactor
        let maxWidth: CGFloat = 500

        let imageURL: URL
        if path.hasPrefix("/") {
            imageURL = URL(fileURLWithPath: path)
        } else if path.hasPrefix("http://") || path.hasPrefix("https://") {
            appendImageFallback(alt: alt, to: output)
            return
        } else {
            imageURL = baseURL.appendingPathComponent(path)
        }

        guard let image = NSImage(contentsOf: imageURL) else {
            appendImageFallback(alt: alt, to: output)
            return
        }

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

    private func applySyntaxHighlighting(to attributed: NSMutableAttributedString, language: String?, font: NSFont) {
        let code = attributed.string
        let fullRange = NSRange(location: 0, length: attributed.length)
        let boldFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold)

        let commentColor = NSColor.secondaryLabelColor
        let stringColor = NSColor.systemGreen
        let keywordColor = NSColor.systemPink
        let numberColor = NSColor.systemBlue
        let typeColor = NSColor.systemPurple

        // Single-line comments (// or #).
        let commentPatterns: [String]
        switch language {
        case "python", "ruby", "bash", "sh", "zsh", "yaml", "yml":
            commentPatterns = ["#[^\n]*"]
        case "html", "xml":
            commentPatterns = ["<!--[\\s\\S]*?-->"]
        default:
            commentPatterns = ["//[^\n]*", "/\\*[\\s\\S]*?\\*/"]
        }

        // Strings (double and single quoted).
        let stringPattern = "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'"

        // Numbers.
        let numberPattern = "\\b\\d+\\.?\\d*\\b"

        // Keywords per language family.
        let keywords: [String]
        switch language {
        case "swift":
            keywords = ["import", "let", "var", "func", "class", "struct", "enum", "protocol",
                        "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
                        "return", "throw", "throws", "try", "catch", "in", "where", "as", "is",
                        "true", "false", "nil", "self", "Self", "super", "init", "deinit",
                        "public", "private", "internal", "fileprivate", "open", "static", "override",
                        "async", "await", "some", "any", "typealias", "associatedtype", "extension",
                        "final", "lazy", "weak", "unowned", "mutating", "nonmutating",
                        "convenience", "required", "optional", "dynamic", "indirect",
                        "break", "continue", "fallthrough", "do", "defer", "inout"]
        case "python":
            keywords = ["import", "from", "def", "class", "if", "elif", "else", "for", "while",
                        "return", "yield", "try", "except", "finally", "raise", "with", "as",
                        "True", "False", "None", "and", "or", "not", "in", "is", "lambda",
                        "pass", "break", "continue", "global", "nonlocal", "assert", "del",
                        "async", "await", "self"]
        case "javascript", "js", "typescript", "ts":
            keywords = ["import", "export", "from", "let", "const", "var", "function", "class",
                        "if", "else", "switch", "case", "default", "for", "while", "do",
                        "return", "throw", "try", "catch", "finally", "new", "delete", "typeof",
                        "true", "false", "null", "undefined", "this", "super",
                        "async", "await", "yield", "of", "in", "instanceof",
                        "break", "continue", "void", "interface", "type", "enum", "extends", "implements"]
        case "go":
            keywords = ["package", "import", "func", "type", "struct", "interface", "map",
                        "if", "else", "switch", "case", "default", "for", "range", "select",
                        "return", "go", "defer", "chan", "var", "const",
                        "true", "false", "nil", "break", "continue", "fallthrough"]
        case "rust":
            keywords = ["use", "mod", "fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl",
                        "if", "else", "match", "for", "while", "loop", "in",
                        "return", "pub", "self", "Self", "super", "crate",
                        "true", "false", "as", "ref", "move", "async", "await", "where",
                        "break", "continue", "unsafe", "dyn", "type"]
        case "java", "kotlin":
            keywords = ["import", "package", "class", "interface", "enum", "extends", "implements",
                        "if", "else", "switch", "case", "default", "for", "while", "do",
                        "return", "throw", "try", "catch", "finally", "new",
                        "true", "false", "null", "this", "super", "void",
                        "public", "private", "protected", "static", "final", "abstract",
                        "break", "continue", "instanceof", "synchronized", "volatile",
                        "var", "val", "fun", "when", "object", "companion", "data", "sealed"]
        case "c", "cpp", "c++", "objc", "objective-c":
            keywords = ["#include", "#import", "#define", "#ifdef", "#ifndef", "#endif", "#pragma",
                        "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                        "if", "else", "switch", "case", "default", "for", "while", "do",
                        "return", "break", "continue", "goto", "sizeof", "typedef",
                        "struct", "union", "enum", "class", "namespace", "template", "typename",
                        "const", "static", "extern", "volatile", "register", "auto",
                        "true", "false", "NULL", "nullptr", "this",
                        "public", "private", "protected", "virtual", "override", "final",
                        "new", "delete", "throw", "try", "catch", "using"]
        case "bash", "sh", "zsh":
            keywords = ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                        "case", "esac", "in", "function", "return", "local", "export",
                        "echo", "exit", "set", "unset", "readonly", "shift", "source",
                        "true", "false"]
        default:
            // Generic: common keywords across languages.
            keywords = ["if", "else", "for", "while", "return", "function", "class", "import",
                        "true", "false", "null", "nil", "let", "var", "const", "def", "fn"]
        }

        // Apply in order: comments and strings first (they take precedence), then keywords and numbers.
        // Track which ranges are already colored to avoid overlapping.
        var colored = IndexSet()

        func applyPattern(_ pattern: String, color: NSColor, bold: Bool = false) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: code, range: fullRange) {
                let range = match.range
                guard !colored.contains(integersIn: range.location..<(range.location + range.length)) else { continue }
                attributed.addAttribute(.foregroundColor, value: color, range: range)
                if bold {
                    attributed.addAttribute(.font, value: boldFont, range: range)
                }
                colored.insert(integersIn: range.location..<(range.location + range.length))
            }
        }

        // Comments first (highest precedence).
        for pattern in commentPatterns {
            applyPattern(pattern, color: commentColor)
        }

        // Strings.
        applyPattern(stringPattern, color: stringColor)

        // Keywords (whole word match).
        if !keywords.isEmpty {
            let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
            let keywordPattern = "\\b(" + escaped.joined(separator: "|") + ")\\b"
            applyPattern(keywordPattern, color: keywordColor, bold: true)
        }

        // Numbers.
        applyPattern(numberPattern, color: numberColor)

        // Types (capitalized identifiers — simple heuristic).
        applyPattern("\\b[A-Z][a-zA-Z0-9]+\\b", color: typeColor)
    }

    private func throwIfCancelled() throws {
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    @MainActor
    private func ensureRenderingCanContinue(
        _ shouldContinue: @MainActor @Sendable () -> Bool
    ) throws {
        try throwIfCancelled()

        guard shouldContinue() else {
            throw CancellationError()
        }
    }

    private func paragraphAttributes() -> [NSAttributedString.Key: Any] {
        return [
            .font: settings.fontFamily.font(ofSize: 15 * settings.textSizeLevel.scaleFactor, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle()
        ]
    }

    private func quoteAttributes() -> [NSAttributedString.Key: Any] {
        let scale = settings.textSizeLevel.scaleFactor
        let padding = 12 * scale

        let textBlock = QuoteBorderTextBlock()
        textBlock.setContentWidth(100, type: .percentageValueType)
        textBlock.setWidth(padding, type: .absoluteValueType, for: .padding, edge: .minX)
        textBlock.setWidth(4, type: .absoluteValueType, for: .padding, edge: .minY)
        textBlock.setWidth(4, type: .absoluteValueType, for: .padding, edge: .maxY)

        let style = bodyParagraphStyle()
        style.textBlocks = [textBlock]

        return [
            .font: settings.fontFamily.font(ofSize: 15 * scale, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ]
    }

    private func listContinuationParagraphAttributes() -> [NSAttributedString.Key: Any] {
        return hangingIndentAttributes(foregroundColor: NSColor.labelColor)
    }

    private func bodyParagraphStyle() -> NSMutableParagraphStyle {
        let scale = settings.textSizeLevel.scaleFactor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4 * scale
        paragraph.paragraphSpacing = 10 * scale
        return paragraph
    }

    private func hangingIndentAttributes(foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
        hangingIndentAttributes(foregroundColor: foregroundColor, depth: 0)
    }

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

    private func codeParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        return paragraph
    }

    private func normalizeLineEndings(in source: String) -> String {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func heading(from line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }

        guard hashes.isEmpty == false, hashes.count <= 6 else {
            return nil
        }

        let remainder = trimmed.dropFirst(hashes.count)
        guard remainder.first?.isWhitespace == true else {
            return nil
        }

        let text = remainder.trimmingCharacters(in: .whitespaces)

        guard text.isEmpty == false else {
            return nil
        }

        return (hashes.count, text)
    }

    private func isFenceLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private func isQuoteLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private func quoteContent(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let body = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        return String(body)
    }

    private func isBulletLine(_ line: String) -> Bool {
        bulletContent(from: line) != nil
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        guard let char = stripped.first, ["-", "*", "_"].contains(char) else { return false }
        return stripped.allSatisfy { $0 == char }
    }

    private func isContinuationParagraphLine(_ line: String) -> Bool {
        line.hasPrefix(" ") || line.hasPrefix("\t")
    }

    private func bulletContent(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("- ") {
            return String(trimmed.dropFirst(2))
        }

        if trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2))
        }

        return nil
    }

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

    private func isBlockStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return true
        }

        if isFenceLine(line) {
            return true
        }

        if heading(from: line) != nil {
            return true
        }

        if isQuoteLine(line) {
            return true
        }

        if isBulletLine(line) {
            return true
        }

        if isOrderedListLine(line) {
            return true
        }

        if isTableLine(line) {
            return true
        }

        if isHorizontalRule(line) {
            return true
        }

        if imageReference(from: line) != nil,
           line.trimmingCharacters(in: .whitespaces).hasPrefix("![") {
            return true
        }

        return false
    }

    private func nextNonBlankLineIndex(in lines: [String], startingAt index: Int) -> Int? {
        var cursor = index

        while cursor < lines.count {
            if lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return cursor
            }

            cursor += 1
        }

        return nil
    }

}

private final class QuoteBorderTextBlock: NSTextBlock {
    override func drawBackground(
        withFrame frameRect: NSRect,
        in controlView: NSView?,
        characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        NSColor.tertiaryLabelColor.setFill()
        let barWidth: CGFloat = 3
        let barRect = NSRect(x: frameRect.minX, y: frameRect.minY, width: barWidth, height: frameRect.height)
        let path = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        path.fill()
    }
}

private final class RoundedTextBlock: NSTextBlock {
    override func drawBackground(
        withFrame frameRect: NSRect,
        in controlView: NSView?,
        characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        guard let color = backgroundColor else { return }
        color.setFill()
        let path = NSBezierPath(roundedRect: frameRect, xRadius: 6, yRadius: 6)
        path.fill()
    }
}

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
