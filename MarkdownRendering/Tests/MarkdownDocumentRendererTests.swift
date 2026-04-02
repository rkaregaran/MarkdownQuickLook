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

    func testRenderPreservesParagraphBreaksInsideMultiParagraphQuote() throws {
        let rendered = renderedTextStorage(from: try renderDocument(
            """
            > first paragraph
            >
            > second paragraph
            """
        ).payload.attributedContent)

        XCTAssertEqual(
            rendered.string,
            "│ first paragraph\n\n│ second paragraph"
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

    func testRenderPreservesFollowOnParagraphsInsideListItems() throws {
        let rendered = renderedTextStorage(from: try renderDocument(
            """
            - first paragraph

              second paragraph in same item
            - next item
            """
        ).payload.attributedContent)

        let nsString = rendered.string as NSString
        let secondParagraphRange = nsString.range(of: "second paragraph in same item")
        let secondParagraphStyle = rendered.attribute(.paragraphStyle, at: secondParagraphRange.location, effectiveRange: nil) as? NSParagraphStyle

        XCTAssertNotEqual(secondParagraphRange.location, NSNotFound)
        XCTAssertGreaterThan(secondParagraphStyle?.headIndent ?? 0, 0)
        XCTAssertGreaterThan(secondParagraphStyle?.firstLineHeadIndent ?? 0, 0)
    }

    func testRenderAppliesHangingIndentToWrappedQuoteParagraphs() throws {
        let rendered = renderedTextStorage(
            from: try renderDocument(
                """
                > This is a long quote paragraph that should wrap in the text view so we can verify the second visual line stays aligned under the quote marker.
                """
            ).payload.attributedContent,
            width: 190
        )

        let nsString = rendered.string as NSString
        let paragraphRange = nsString.range(of: "This is a long quote paragraph")

        XCTAssertNotEqual(paragraphRange.location, NSNotFound)
        let paragraphStyle = rendered.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
        let wrappedLineCount = lineFragmentCount(in: rendered, for: paragraphRange)

        XCTAssertGreaterThan(wrappedLineCount, 1)
        XCTAssertEqual(paragraphStyle?.firstLineHeadIndent, 24)
        XCTAssertEqual(paragraphStyle?.headIndent, 24)
    }

    func testRenderAppliesHangingIndentToWrappedFirstBulletParagraph() throws {
        let rendered = renderedTextStorage(
            from: try renderDocument(
                """
                - This is a long bullet item paragraph that should wrap in the text view so the continuation line keeps the same bullet text column.
                """
            ).payload.attributedContent,
            width: 190
        )

        let nsString = rendered.string as NSString
        let paragraphRange = nsString.range(of: "This is a long bullet item paragraph")

        XCTAssertNotEqual(paragraphRange.location, NSNotFound)
        let paragraphStyle = rendered.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
        let wrappedLineCount = lineFragmentCount(in: rendered, for: paragraphRange)

        XCTAssertGreaterThan(wrappedLineCount, 1)
        XCTAssertEqual(paragraphStyle?.firstLineHeadIndent, 24)
        XCTAssertEqual(paragraphStyle?.headIndent, 24)
    }

    func testRenderTreatsCRLFInputLikeLFInputForSupportedBlocks() throws {
        let lfMarkdown = """
        Paragraph one

        > Quote line one
        > quote line two

        - Bullet line one
          bullet continuation

        ```
        let value = 1
        let doubled = value * 2
        ```
        """
        let crlfMarkdown = lfMarkdown.replacingOccurrences(of: "\n", with: "\r\n")

        let lfPayload = try renderDocument(lfMarkdown).payload
        let crlfPayload = try renderDocument(crlfMarkdown).payload

        XCTAssertEqual(
            crlfPayload.attributedContent.string,
            lfPayload.attributedContent.string
        )
        XCTAssertEqual(
            crlfPayload.attributedContent.string,
            "Paragraph one\n\n│ Quote line one quote line two\n\n• Bullet line one bullet continuation\n\nlet value = 1\nlet doubled = value * 2"
        )
    }

    func testRenderUsesTightParagraphSpacingForCodeBlocksInTextView() throws {
        let rendered = renderedTextStorage(
            from: try renderDocument(
                """
                ```
                let value = 1
                let doubled = value * 2
                ```
                """
            ).payload.attributedContent,
            width: 260
        )

        let nsString = rendered.string as NSString
        let codeRange = nsString.range(of: "let value = 1\nlet doubled = value * 2")

        XCTAssertNotEqual(codeRange.location, NSNotFound)
        let paragraphStyle = rendered.attribute(.paragraphStyle, at: codeRange.location, effectiveRange: nil) as? NSParagraphStyle
        let lineFragments = lineFragmentCount(in: rendered, for: codeRange)

        XCTAssertEqual(lineFragments, 2)
        XCTAssertEqual(paragraphStyle?.lineSpacing, 0)
        XCTAssertEqual(paragraphStyle?.paragraphSpacing, 0)
        XCTAssertEqual(paragraphStyle?.paragraphSpacingBefore, 0)
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

    private func renderedTextStorage(from attributedContent: NSAttributedString, width: CGFloat = 320) -> NSTextStorage {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1000))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(attributedContent)
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }

        return textView.textStorage ?? NSTextStorage(attributedString: attributedContent)
    }

    private func lineFragmentCount(in textStorage: NSTextStorage, for characterRange: NSRange) -> Int {
        guard let layoutManager = textStorage.layoutManagers.first else {
            return 0
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        var count = 0

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
            count += 1
        }

        return count
    }
}
