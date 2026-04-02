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

public enum MarkdownDocumentRendererError: Error, Equatable, LocalizedError {
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

public final class MarkdownDocumentRenderer {
    public init() {}

    public func render(fileAt url: URL) throws -> MarkdownRenderPayload {
        let source: String

        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MarkdownDocumentRendererError.unreadableFile(url)
        }

        guard source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MarkdownDocumentRendererError.emptyDocument(url)
        }

        let blocks = parseBlocks(in: source)
        let formatted = NSMutableAttributedString()
        let baseURL = url.deletingLastPathComponent()

        for (index, block) in blocks.enumerated() {
            append(block, to: formatted, baseURL: baseURL)

            if index < blocks.count - 1 {
                formatted.append(NSAttributedString(string: "\n\n"))
            }
        }

        return MarkdownRenderPayload(
            title: url.lastPathComponent,
            attributedContent: formatted
        )
    }

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case paragraph(String)
        case quote(String)
        case list([String])
        case code(String)
    }

    private func parseBlocks(in source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
                continue
            }

            if let codeBlock = parseFencedCodeBlock(from: lines, startingAt: index) {
                blocks.append(.code(codeBlock.text))
                index = codeBlock.nextIndex
                continue
            }

            if let heading = heading(from: lines[index]) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if let quote = parseQuoteBlock(from: lines, startingAt: index) {
                blocks.append(.quote(quote.text))
                index = quote.nextIndex
                continue
            }

            if let list = parseListBlock(from: lines, startingAt: index) {
                blocks.append(.list(list.items))
                index = list.nextIndex
                continue
            }

            let paragraph = parseParagraph(from: lines, startingAt: index)
            blocks.append(.paragraph(paragraph.text))
            index = paragraph.nextIndex
        }

        return blocks
    }

    private func parseFencedCodeBlock(from lines: [String], startingAt index: Int) -> (text: String, nextIndex: Int)? {
        guard isFenceLine(lines[index]) else {
            return nil
        }

        var codeLines: [String] = []
        var cursor = index + 1

        while cursor < lines.count, isFenceLine(lines[cursor]) == false {
            codeLines.append(lines[cursor])
            cursor += 1
        }

        if cursor < lines.count, isFenceLine(lines[cursor]) {
            cursor += 1
        }

        return (codeLines.joined(separator: "\n"), cursor)
    }

    private func parseQuoteBlock(from lines: [String], startingAt index: Int) -> (text: String, nextIndex: Int)? {
        guard isQuoteLine(lines[index]) else {
            return nil
        }

        var quoteLines: [String] = []
        var cursor = index

        while cursor < lines.count, isQuoteLine(lines[cursor]) {
            quoteLines.append(quoteContent(from: lines[cursor]))
            cursor += 1
        }

        return (quoteLines.joined(separator: " "), cursor)
    }

    private func parseListBlock(from lines: [String], startingAt index: Int) -> (items: [String], nextIndex: Int)? {
        guard isBulletLine(lines[index]) else {
            return nil
        }

        var items: [String] = []
        var cursor = index

        while cursor < lines.count, isBulletLine(lines[cursor]) {
            let item = parseListItem(from: lines, startingAt: cursor)
            items.append(item.text)
            cursor = item.nextIndex
        }

        return (items, cursor)
    }

    private func parseListItem(from lines: [String], startingAt index: Int) -> (text: String, nextIndex: Int) {
        let firstLine = bulletContent(from: lines[index]) ?? ""
        var parts = [firstLine]
        var cursor = index + 1

        while cursor < lines.count {
            let line = lines[cursor]

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                break
            }

            if isBlockStart(line) {
                break
            }

            guard line.hasPrefix(" ") || line.hasPrefix("\t") else {
                break
            }

            parts.append(line.trimmingCharacters(in: .whitespaces))
            cursor += 1
        }

        return (parts.joined(separator: " "), cursor)
    }

    private func parseParagraph(from lines: [String], startingAt index: Int) -> (text: String, nextIndex: Int) {
        var parts = [lines[index].trimmingCharacters(in: .whitespaces)]
        var cursor = index + 1

        while cursor < lines.count {
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

        case .quote(let text):
            appendInlineMarkdown("│ \(text)", baseURL: baseURL, baseAttributes: quoteAttributes(), to: output)

        case .list(let items):
            for (index, item) in items.enumerated() {
                appendInlineMarkdown("• \(item)", baseURL: baseURL, baseAttributes: paragraphAttributes(), to: output)

                if index < items.count - 1 {
                    output.append(NSAttributedString(string: "\n"))
                }
            }

        case .code(let text):
            appendCodeBlock(text, to: output)
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
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 10

        attributed.addAttribute(.foregroundColor, value: headingColor, range: fullRange)
        attributed.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)

        attributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let baseFont = (value as? NSFont) ?? headingBaseFont(for: level)
            let styledFont = headingFont(for: baseFont, level: level)
            attributed.addAttribute(.font, value: styledFont, range: range)
        }
    }

    private func headingBaseFont(for level: Int) -> NSFont {
        switch level {
        case 1:
            return NSFont.systemFont(ofSize: 30, weight: .semibold)
        case 2:
            return NSFont.systemFont(ofSize: 24, weight: .semibold)
        case 3:
            return NSFont.systemFont(ofSize: 20, weight: .semibold)
        default:
            return NSFont.systemFont(ofSize: 17, weight: .semibold)
        }
    }

    private func headingFont(for baseFont: NSFont, level: Int) -> NSFont {
        let sizedFont = baseFont.isFixedPitch ? NSFont.monospacedSystemFont(ofSize: headingSize(for: level), weight: .semibold) : NSFont.systemFont(ofSize: headingSize(for: level), weight: .semibold)
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
        switch level {
        case 1:
            return 30
        case 2:
            return 24
        case 3:
            return 20
        default:
            return 17
        }
    }

    private func appendCodeBlock(_ code: String, to output: NSMutableAttributedString) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 10

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.textBackgroundColor,
            .paragraphStyle: paragraph
        ]

        output.append(NSAttributedString(string: code, attributes: attributes))
    }

    private func paragraphAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 10

        return [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private func quoteAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 10

        return [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
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

        return false
    }

}
