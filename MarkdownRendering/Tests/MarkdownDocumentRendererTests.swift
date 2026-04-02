import AppKit
import XCTest
@testable import MarkdownRendering

final class MarkdownDocumentRendererTests: XCTestCase {
    func testRenderKeepsWrappedParagraphLinesTogether() throws {
        let document = try renderDocument(
            """
            First line of a paragraph
            wrapped continuation

            Second paragraph
            """
        )

        XCTAssertEqual(document.payload.title, document.url.lastPathComponent)
        XCTAssertEqual(
            document.payload.attributedContent.string,
            "First line of a paragraph wrapped continuation\n\nSecond paragraph"
        )
    }

    func testRenderKeepsMultiLineQuoteTogether() throws {
        let payload = try renderDocument(
            """
            > First quote line
            > second quote line

            After quote
            """
        ).payload

        XCTAssertEqual(
            payload.attributedContent.string,
            "│ First quote line second quote line\n\nAfter quote"
        )
    }

    func testRenderKeepsMultiLineListItemTogether() throws {
        let payload = try renderDocument(
            """
            - First list line
              continuation line
            - Second item
            """
        ).payload

        XCTAssertEqual(
            payload.attributedContent.string,
            "• First list line continuation line\n• Second item"
        )
    }

    func testRenderPreservesFencedCodeBlockContentAndStyle() throws {
        let payload = try renderDocument(
            """
            Before

            ```
            let value = 1
            let doubled = value * 2
            ```

            After
            """
        ).payload

        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString
        let codeRange = nsString.range(of: "let value = 1\nlet doubled = value * 2")
        let font = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont

        XCTAssertNotEqual(codeRange.location, NSNotFound)
        XCTAssertEqual(
            rendered.string,
            "Before\n\nlet value = 1\nlet doubled = value * 2\n\nAfter"
        )
        XCTAssertTrue(font?.isFixedPitch == true)
    }

    func testRenderPreservesBodyInlineCodeThroughTextViewRendering() throws {
        let payload = try renderDocument("Paragraph with `code` and **bold** text.").payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString

        let codeRange = nsString.range(of: "code")
        let boldRange = nsString.range(of: "bold")
        let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        let boldFont = rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont

        XCTAssertNotEqual(codeRange.location, NSNotFound)
        XCTAssertNotEqual(boldRange.location, NSNotFound)
        XCTAssertTrue(codeFont?.isFixedPitch == true)
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    func testRenderPreservesHeadingInlineCodeThroughTextViewRendering() throws {
        let payload = try renderDocument("# Heading with `code`").payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString
        let codeRange = nsString.range(of: "code")
        let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont

        XCTAssertNotEqual(codeRange.location, NSNotFound)
        XCTAssertTrue(codeFont?.isFixedPitch == true)
        XCTAssertEqual(codeFont?.pointSize, 30)
    }

    func testRenderPreservesHeadingInlineLinkAttributes() throws {
        let payload = try renderDocument("# Heading with [OpenAI](https://openai.com)").payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString
        let range = nsString.range(of: "OpenAI")
        let link = rendered.attribute(.link, at: range.location, effectiveRange: nil) as? URL

        XCTAssertEqual(link, URL(string: "https://openai.com"))
    }

    func testRenderDoesNotTreatHashPrefixedTextWithoutSpaceAsHeading() throws {
        let payload = try renderDocument(
            """
            #hashtag
            ##Heading
            """
        ).payload

        XCTAssertTrue(payload.attributedContent.string.contains("#hashtag"))
        XCTAssertTrue(payload.attributedContent.string.contains("##Heading"))
    }

    func testRenderThrowsEmptyDocumentForWhitespaceOnlyInput() throws {
        let url = try temporaryMarkdownFile("   \n\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MarkdownDocumentRenderer().render(fileAt: url)) { error in
            XCTAssertEqual(error as? MarkdownDocumentRendererError, .emptyDocument(url))
        }
    }

    func testRenderThrowsUnreadableFileWhenFileIsMissing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        XCTAssertThrowsError(try MarkdownDocumentRenderer().render(fileAt: url)) { error in
            XCTAssertEqual(error as? MarkdownDocumentRendererError, .unreadableFile(url))
        }
    }

    private func temporaryMarkdownFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func renderDocument(_ contents: String) throws -> (url: URL, payload: MarkdownRenderPayload) {
        let url = try temporaryMarkdownFile(contents)
        defer { try? FileManager.default.removeItem(at: url) }
        let payload = try MarkdownDocumentRenderer().render(fileAt: url)
        return (url, payload)
    }

    private func renderedTextStorage(from attributedContent: NSAttributedString) -> NSTextStorage {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(attributedContent)
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }

        return textView.textStorage ?? NSTextStorage(attributedString: attributedContent)
    }
}
