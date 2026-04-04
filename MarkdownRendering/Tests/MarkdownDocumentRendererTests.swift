import AppKit
import XCTest
@testable import MarkdownRendering

@MainActor
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
            "First quote line second quote line\n\nAfter quote"
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
            "first paragraph\n\nsecond paragraph"
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

    func testRenderAppliesTextBlockToQuoteParagraphs() throws {
        let rendered = renderedTextStorage(
            from: try renderDocument(
                """
                > This is a quote paragraph that uses a text block for the left border.
                """
            ).payload.attributedContent,
            width: 190
        )

        let nsString = rendered.string as NSString
        let paragraphRange = nsString.range(of: "This is a quote paragraph")

        XCTAssertNotEqual(paragraphRange.location, NSNotFound)
        let paragraphStyle = rendered.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
        let foregroundColor = rendered.attribute(.foregroundColor, at: paragraphRange.location, effectiveRange: nil) as? NSColor

        XCTAssertNotNil(paragraphStyle?.textBlocks.first)
        XCTAssertEqual(foregroundColor, NSColor.secondaryLabelColor)
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
            "Paragraph one\n\nQuote line one quote line two\n\n• Bullet line one bullet continuation\n\nlet value = 1\nlet doubled = value * 2"
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
        XCTAssertEqual(paragraphStyle?.lineSpacing, 2)
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

    func testPreparedDocumentRendersSameContentAsDirectRender() async throws {
        let url = try temporaryMarkdownFile(
            """
            # Title

            Paragraph with [OpenAI](https://openai.com).

            - Bullet item
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let renderer = MarkdownDocumentRenderer()

        let directPayload = try await MainActor.run {
            try renderer.render(fileAt: url)
        }
        let preparedDocument = try renderer.prepareDocument(fileAt: url)
        let preparedPayload = await MainActor.run {
            renderer.render(document: preparedDocument)
        }

        XCTAssertEqual(preparedDocument.title, url.lastPathComponent)
        XCTAssertEqual(preparedPayload.title, directPayload.title)
        XCTAssertEqual(preparedPayload.attributedContent.string, directPayload.attributedContent.string)
    }

    func testPreparedDocumentSupportsOffMainPreparation() async throws {
        let url = try temporaryMarkdownFile(
            """
            # Title

            Paragraph with `code`.
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let preparedDocument = try await Task.detached(priority: .userInitiated) {
            try MarkdownDocumentRenderer().prepareDocument(fileAt: url)
        }.value

        let payload = await MainActor.run {
            MarkdownDocumentRenderer().render(document: preparedDocument)
        }

        XCTAssertEqual(preparedDocument.title, url.lastPathComponent)
        XCTAssertTrue(payload.attributedContent.string.contains("Title"))
        XCTAssertTrue(payload.attributedContent.string.contains("Paragraph with code."))
    }

    private func temporaryMarkdownFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testRenderWithLargeTextSizeProducesLargerBodyFont() throws {
        let largeSettings = MarkdownRenderSettings(textSizeLevel: .large, fontFamily: .system)
        let payload = try renderDocument("Hello world", settings: largeSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize ?? 0, 15 * 1.10, accuracy: 0.01)
    }

    func testRenderWithExtraSmallTextSizeProducesSmallerBodyFont() throws {
        let smallSettings = MarkdownRenderSettings(textSizeLevel: .extraSmall, fontFamily: .system)
        let payload = try renderDocument("Hello world", settings: smallSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize ?? 0, 15 * 0.80, accuracy: 0.01)
    }

    func testRenderWithSerifFontUsesSerifForBody() throws {
        let serifSettings = MarkdownRenderSettings(textSizeLevel: .medium, fontFamily: .serif)
        let payload = try renderDocument("Hello world", settings: serifSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let systemFont = NSFont.systemFont(ofSize: 15)

        XCTAssertNotEqual(font?.fontName, systemFont.fontName)
    }

    func testRenderWithMonospacedFontUsesFixedPitchForBody() throws {
        let monoSettings = MarkdownRenderSettings(textSizeLevel: .medium, fontFamily: .monospaced)
        let payload = try renderDocument("Hello world", settings: monoSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertTrue(font?.isFixedPitch == true)
    }

    func testRenderCodeBlockStaysMonospacedRegardlessOfFontFamily() throws {
        let serifSettings = MarkdownRenderSettings(textSizeLevel: .medium, fontFamily: .serif)
        let payload = try renderDocument("```\nlet x = 1\n```", settings: serifSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertTrue(font?.isFixedPitch == true)
    }

    func testRenderHeadingScalesWithTextSizeLevel() throws {
        let largeSettings = MarkdownRenderSettings(textSizeLevel: .large, fontFamily: .system)
        let payload = try renderDocument("# Title", settings: largeSettings).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(font?.pointSize ?? 0, 30 * 1.10, accuracy: 0.01)
    }

    func testDefaultSettingsProduceSameFontSizesAsBeforeSettingsFeature() throws {
        let payload = try renderDocument("# Title\n\nBody text\n\n```\ncode\n```").payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString

        let titleRange = nsString.range(of: "Title")
        let bodyRange = nsString.range(of: "Body text")
        let codeRange = nsString.range(of: "code")

        let titleFont = rendered.attribute(.font, at: titleRange.location, effectiveRange: nil) as? NSFont
        let bodyFont = rendered.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont
        let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont

        XCTAssertEqual(titleFont?.pointSize, 30)
        XCTAssertEqual(bodyFont?.pointSize, 15)
        XCTAssertEqual(codeFont?.pointSize, 13)
    }

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
        XCTAssertTrue(text.contains("not front matter"))
    }

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
        XCTAssertTrue(payload.attributedContent.string.contains("Text with"))
    }

    private func renderDocument(_ contents: String, settings: MarkdownRenderSettings = .default) throws -> (url: URL, payload: MarkdownRenderPayload) {
        let url = try temporaryMarkdownFile(contents)
        defer { try? FileManager.default.removeItem(at: url) }
        let payload = try MarkdownDocumentRenderer(settings: settings).render(fileAt: url)
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
