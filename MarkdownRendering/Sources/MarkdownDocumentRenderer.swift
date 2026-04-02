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

        let formatted = NSMutableAttributedString()
        let baseURL = url.deletingLastPathComponent()
        var isInsideCodeFence = false
        var fencedCodeLines: [String] = []

        for line in source.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if isInsideCodeFence {
                    appendCodeBlock(fencedCodeLines.joined(separator: "\n"), to: formatted)
                    fencedCodeLines.removeAll()
                    isInsideCodeFence = false
                } else {
                    isInsideCodeFence = true
                }
                continue
            }

            if isInsideCodeFence {
                fencedCodeLines.append(line)
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                ensureBlankLine(in: formatted)
                continue
            }

            if let heading = heading(from: line) {
                appendStyledText(heading.text, attributes: headingAttributes(level: heading.level), to: formatted)
                ensureBlankLine(in: formatted)
                continue
            }

            if let listItem = listItem(from: line) {
                appendInlineMarkdown("• \(listItem)", baseURL: baseURL, baseAttributes: bodyAttributes(), to: formatted)
                appendNewline(to: formatted)
                continue
            }

            if let quote = blockQuote(from: line) {
                appendInlineMarkdown("│ \(quote)", baseURL: baseURL, baseAttributes: quoteAttributes(), to: formatted)
                ensureBlankLine(in: formatted)
                continue
            }

            appendInlineMarkdown(line, baseURL: baseURL, baseAttributes: bodyAttributes(), to: formatted)
            ensureBlankLine(in: formatted)
        }

        if isInsideCodeFence, fencedCodeLines.isEmpty == false {
            appendCodeBlock(fencedCodeLines.joined(separator: "\n"), to: formatted)
        }

        return MarkdownRenderPayload(
            title: url.lastPathComponent,
            attributedContent: formatted
        )
    }

    private func heading(from line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }

        guard hashes.isEmpty == false, hashes.count <= 6 else {
            return nil
        }

        let text = trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard text.isEmpty == false else {
            return nil
        }

        return (hashes.count, text)
    }

    private func listItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("- ") {
            return String(trimmed.dropFirst(2))
        }

        if trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2))
        }

        return nil
    }

    private func blockQuote(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("> ") else {
            return nil
        }

        return String(trimmed.dropFirst(2))
    }

    private func appendInlineMarkdown(
        _ text: String,
        baseURL: URL,
        baseAttributes: [NSAttributedString.Key: Any],
        to output: NSMutableAttributedString
    ) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: text, options: options, baseURL: baseURL)) ?? AttributedString(text)
        let attributed = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))
        output.append(attributed)
    }

    private func appendStyledText(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        to output: NSMutableAttributedString
    ) {
        output.append(NSAttributedString(string: text, attributes: attributes))
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
        ensureBlankLine(in: output)
    }

    private func ensureBlankLine(in output: NSMutableAttributedString) {
        let suffix = output.string

        if suffix.hasSuffix("\n\n") {
            return
        }

        if suffix.hasSuffix("\n") {
            output.append(NSAttributedString(string: "\n"))
        } else {
            output.append(NSAttributedString(string: "\n\n"))
        }
    }

    private func appendNewline(to output: NSMutableAttributedString) {
        output.append(NSAttributedString(string: "\n"))
    }

    private func bodyAttributes() -> [NSAttributedString.Key: Any] {
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

    private func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let size: CGFloat

        switch level {
        case 1:
            size = 30
        case 2:
            size = 24
        case 3:
            size = 20
        default:
            size = 17
        }

        return [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
    }
}
