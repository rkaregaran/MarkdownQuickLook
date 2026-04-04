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
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote([String])
    case list([MarkdownListItem])
    case code(String)
    case table(MarkdownTable)
}

struct MarkdownTable: Sendable {
    let headers: [String]
    let rows: [[String]]
}

struct MarkdownListItem: Sendable {
    let paragraphs: [String]
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

        while index < lines.count {
            try throwIfCancelled()

            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
                continue
            }

            if let codeBlock = try parseFencedCodeBlock(from: lines, startingAt: index) {
                blocks.append(.code(codeBlock.text))
                index = codeBlock.nextIndex
                continue
            }

            if let heading = heading(from: lines[index]) {
                blocks.append(.heading(level: heading.level, text: heading.text))
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

            if let table = try parseTableBlock(from: lines, startingAt: index) {
                blocks.append(.table(table.table))
                index = table.nextIndex
                continue
            }

            let paragraph = try parseParagraph(from: lines, startingAt: index)
            blocks.append(.paragraph(paragraph.text))
            index = paragraph.nextIndex
        }

        return blocks
    }

    private func parseFencedCodeBlock(from lines: [String], startingAt index: Int) throws -> (text: String, nextIndex: Int)? {
        guard isFenceLine(lines[index]) else {
            return nil
        }

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

        return (codeLines.joined(separator: "\n"), cursor)
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

    private func parseListBlock(from lines: [String], startingAt index: Int) throws -> (items: [MarkdownListItem], nextIndex: Int)? {
        guard isBulletLine(lines[index]) else {
            return nil
        }

        var items: [MarkdownListItem] = []
        var cursor = index

        while cursor < lines.count, isBulletLine(lines[cursor]) {
            try throwIfCancelled()
            let item = try parseListItem(from: lines, startingAt: cursor)
            items.append(item.item)
            cursor = item.nextIndex
        }

        return (items, cursor)
    }

    private func parseListItem(from lines: [String], startingAt index: Int) throws -> (item: MarkdownListItem, nextIndex: Int) {
        let firstLine = bulletContent(from: lines[index]) ?? ""
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

            if isBlockStart(line) {
                break
            }

            guard isContinuationParagraphLine(line) else {
                break
            }

            let content = line.trimmingCharacters(in: .whitespaces)

            if currentParagraph.isEmpty {
                currentParagraph = content
            } else {
                currentParagraph += " " + content
            }

            cursor += 1
        }

        if currentParagraph.isEmpty == false {
            paragraphs.append(currentParagraph)
        }

        return (MarkdownListItem(paragraphs: paragraphs), cursor)
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
            for (index, paragraph) in paragraphs.enumerated() {
                if index > 0 {
                    output.append(NSAttributedString(string: "\n\n"))
                }

                appendInlineMarkdown("│ \(paragraph)", baseURL: baseURL, baseAttributes: quoteAttributes(), to: output)
            }

        case .list(let items):
            for (itemIndex, item) in items.enumerated() {
                for (paragraphIndex, paragraph) in item.paragraphs.enumerated() {
                    if itemIndex == 0 && paragraphIndex == 0 {
                        appendInlineMarkdown("• \(paragraph)", baseURL: baseURL, baseAttributes: hangingIndentAttributes(foregroundColor: NSColor.labelColor), to: output)
                    } else if paragraphIndex == 0 {
                        appendInlineMarkdown("• \(paragraph)", baseURL: baseURL, baseAttributes: hangingIndentAttributes(foregroundColor: NSColor.labelColor), to: output)
                    } else {
                        output.append(NSAttributedString(string: "\n\n"))
                        appendInlineMarkdown(paragraph, baseURL: baseURL, baseAttributes: listContinuationParagraphAttributes(), to: output)
                    }
                }

                if itemIndex < items.count - 1 {
                    output.append(NSAttributedString(string: "\n"))
                }
            }

        case .code(let text):
            appendCodeBlock(text, to: output)

        case .table(let table):
            appendTable(table, to: output)
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
        return attributed
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

    private func appendCodeBlock(_ code: String, to output: NSMutableAttributedString) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13 * settings.textSizeLevel.scaleFactor, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.textBackgroundColor,
            .paragraphStyle: codeParagraphStyle()
        ]

        output.append(NSAttributedString(string: code, attributes: attributes))
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
        return hangingIndentAttributes(foregroundColor: NSColor.secondaryLabelColor)
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

    private func hangingIndentParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = bodyParagraphStyle()
        let indent = 24 * settings.textSizeLevel.scaleFactor
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        return paragraph
    }

    private func hangingIndentAttributes(foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: settings.fontFamily.font(ofSize: 15 * settings.textSizeLevel.scaleFactor, weight: .regular),
            .foregroundColor: foregroundColor,
            .paragraphStyle: hangingIndentParagraphStyle()
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

        if isTableLine(line) {
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
