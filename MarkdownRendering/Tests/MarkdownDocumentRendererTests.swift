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

    func testRenderSyntaxHighlightingColorsSwiftTokens() throws {
        let payload = try renderDocument(
            """
            ```swift
            struct Widget {
                let count = 42
                let label = "Ready"
            }
            ```
            """
        ).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString

        let structRange = nsString.range(of: "struct")
        let widgetRange = nsString.range(of: "Widget")
        let numberRange = nsString.range(of: "42")
        let stringRange = nsString.range(of: "\"Ready\"")

        let structColor = rendered.attribute(.foregroundColor, at: structRange.location, effectiveRange: nil) as? NSColor
        let widgetColor = rendered.attribute(.foregroundColor, at: widgetRange.location, effectiveRange: nil) as? NSColor
        let numberColor = rendered.attribute(.foregroundColor, at: numberRange.location, effectiveRange: nil) as? NSColor
        let stringColor = rendered.attribute(.foregroundColor, at: stringRange.location, effectiveRange: nil) as? NSColor
        let keywordFont = rendered.attribute(.font, at: structRange.location, effectiveRange: nil) as? NSFont

        XCTAssertEqual(structColor, NSColor.systemPink)
        XCTAssertEqual(widgetColor, NSColor.systemPurple)
        XCTAssertEqual(numberColor, NSColor.systemBlue)
        XCTAssertEqual(stringColor, NSColor.systemGreen)
        XCTAssertTrue(keywordFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    func testRenderSyntaxHighlightingDoesNotOverwriteCommentColor() throws {
        let payload = try renderDocument(
            """
            ```swift
            // let Widget = 42
            let value = 1
            ```
            """
        ).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString

        let commentKeywordRange = nsString.range(of: "let Widget")
        let realKeywordRange = nsString.range(of: "let value")

        let commentColor = rendered.attribute(.foregroundColor, at: commentKeywordRange.location, effectiveRange: nil) as? NSColor
        let realKeywordColor = rendered.attribute(.foregroundColor, at: realKeywordRange.location, effectiveRange: nil) as? NSColor

        XCTAssertEqual(commentColor, NSColor.secondaryLabelColor)
        XCTAssertEqual(realKeywordColor, NSColor.systemPink)
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
        // -- is converted to en dash (–), not a horizontal rule.
        XCTAssertTrue(payload.attributedContent.string.contains("\u{2013}"))
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

    func testRenderPlainTextWithoutInlineMarkersKeepsBodyAttributes() throws {
        let payload = try renderDocument("Plain paragraph without inline markers.").payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let fullRange = NSRange(location: 0, length: rendered.length)
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let color = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let paragraphStyle = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

        XCTAssertEqual(rendered.string, "Plain paragraph without inline markers.")
        XCTAssertEqual(fullRange.length, rendered.string.count)
        XCTAssertEqual(font?.pointSize, 15)
        XCTAssertEqual(color, NSColor.labelColor)
        XCTAssertEqual(paragraphStyle?.paragraphSpacing, 10)
    }

    func testRenderPlainTextDashReplacementStillWorksWithoutInlineParsing() throws {
        let payload = try renderDocument("Before -- middle --- after").payload

        XCTAssertEqual(payload.attributedContent.string, "Before – middle — after")
    }

    func testRenderDashReplacementDoesNotChangeInlineCode() throws {
        let payload = try renderDocument("Use `--flag` before --- launch").payload

        XCTAssertEqual(payload.attributedContent.string, "Use --flag before — launch")
    }

    func testRenderInlineMarkdownFeatureMixAfterFastPath() throws {
        let payload = try renderDocument("Read [docs](https://example.com), **bold**, *italic*, `code`, and ~~old~~ text.").payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString

        let docsRange = nsString.range(of: "docs")
        let boldRange = nsString.range(of: "bold")
        let italicRange = nsString.range(of: "italic")
        let codeRange = nsString.range(of: "code")
        let oldRange = nsString.range(of: "old text")

        let link = rendered.attribute(.link, at: docsRange.location, effectiveRange: nil) as? URL
        let boldFont = rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        let italicFont = rendered.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
        let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        let strike = rendered.attribute(.strikethroughStyle, at: oldRange.location, effectiveRange: nil) as? Int

        XCTAssertEqual(link, URL(string: "https://example.com"))
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertTrue(italicFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        XCTAssertTrue(codeFont?.isFixedPitch == true)
        XCTAssertEqual(strike, NSUnderlineStyle.single.rawValue)
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

    func testRenderMermaidCodeBlockHasLabel() throws {
        let payload = try renderDocument(
            """
            ```mermaid
            graph TD
              A --> B
            ```
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertTrue(text.contains("Mermaid Diagram"))
        XCTAssertTrue(text.contains("graph TD"))
    }

    func testRenderMathCodeBlockHasLabel() throws {
        let payload = try renderDocument(
            """
            ```latex
            E = mc^2
            ```
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertTrue(text.contains("Math Expression"))
        XCTAssertTrue(text.contains("E = mc^2"))
    }

    func testRenderRegularCodeBlockHasNoLabel() throws {
        let payload = try renderDocument(
            """
            ```swift
            let x = 1
            ```
            """
        ).payload

        let text = payload.attributedContent.string
        XCTAssertFalse(text.contains("Diagram"))
        XCTAssertFalse(text.contains("Expression"))
        XCTAssertTrue(text.contains("let x = 1"))
    }

    func testRenderEmitsEmptyTableOfContentsForDocumentWithoutHeadings() throws {
        let payload = try renderDocument("Just a paragraph, no headings here.").payload
        XCTAssertEqual(payload.tableOfContents, [])
    }

    func testRenderEmitsAnchorForEachHeadingInDocumentOrder() throws {
        let payload = try renderDocument(
            """
            # Top level
            Body.

            ## Second
            More body.

            ### Third
            Final body.
            """
        ).payload

        XCTAssertEqual(payload.tableOfContents.map(\.level), [1, 2, 3])
        XCTAssertEqual(payload.tableOfContents.map(\.text), ["Top level", "Second", "Third"])

        let locations = payload.tableOfContents.map(\.range.location)
        XCTAssertEqual(locations, locations.sorted(), "Anchors must be in document order")
    }

    func testRenderEmitsAllSixHeadingLevels() throws {
        let payload = try renderDocument(
            """
            # H1

            ## H2

            ### H3

            #### H4

            ##### H5

            ###### H6
            """
        ).payload

        XCTAssertEqual(payload.tableOfContents.map(\.level), [1, 2, 3, 4, 5, 6])
    }

    func testRenderAnchorRangeMatchesHeadingPositionInRenderedString() throws {
        let payload = try renderDocument(
            """
            Intro paragraph.

            # First Heading

            Some body text after the heading.

            ## Second Heading

            More text.
            """
        ).payload

        let rendered = payload.attributedContent.string as NSString
        XCTAssertEqual(payload.tableOfContents.count, 2)

        for anchor in payload.tableOfContents {
            let plainHeading: String
            if let parsed = try? AttributedString(markdown: anchor.text) {
                plainHeading = String(parsed.characters)
            } else {
                plainHeading = anchor.text
            }

            let location = anchor.range.location
            XCTAssertLessThanOrEqual(
                location + plainHeading.count,
                rendered.length,
                "Anchor location for level \(anchor.level) is past end of rendered string"
            )

            let suffix = rendered.substring(from: location)
            XCTAssertTrue(
                suffix.hasPrefix(plainHeading),
                "Rendered string at anchor location for level \(anchor.level) should start with \(plainHeading); got \(suffix.prefix(plainHeading.count))"
            )
        }
    }

    func testAsyncRenderEmitsHeadingAnchors() async throws {
        let url = try temporaryMarkdownFile(
            """
            # Async One

            Body text.

            ## Async Two
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let renderer = MarkdownDocumentRenderer()
        let document = try renderer.prepareDocument(fileAt: url)
        let payload = try await renderer.render(document: document, shouldContinue: { true })

        XCTAssertEqual(payload.tableOfContents.map(\.level), [1, 2])
        XCTAssertEqual(payload.tableOfContents.map(\.text), ["Async One", "Async Two"])
    }

    func testTableOfContentsForSampleFixture() throws {
        let fixtureURL = sampleFixtureURL(named: "Sample.md")
        let payload = try MarkdownDocumentRenderer().render(fileAt: fixtureURL)

        let levels = payload.tableOfContents.map(\.level)
        let texts = payload.tableOfContents.map(\.text)

        XCTAssertEqual(levels, [1, 2, 2, 2, 2, 2])
        XCTAssertEqual(
            texts,
            [
                "Markdown Quick Look",
                "Checklist",
                "Features",
                "Ordered Steps",
                "Nested Lists",
                "Image Test"
            ]
        )

        let rendered = payload.attributedContent.string as NSString
        for anchor in payload.tableOfContents {
            let plainHeading: String
            if let parsed = try? AttributedString(markdown: anchor.text) {
                plainHeading = String(parsed.characters)
            } else {
                plainHeading = anchor.text
            }

            XCTAssertLessThanOrEqual(
                anchor.range.location + plainHeading.count,
                rendered.length,
                "Anchor location for level \(anchor.level) is past end of rendered string"
            )

            let suffix = rendered.substring(from: anchor.range.location)
            XCTAssertTrue(
                suffix.hasPrefix(plainHeading),
                "Rendered string at anchor location for level \(anchor.level) should start with \(plainHeading)"
            )
        }
    }

    func testTableOfContentsForShowcaseFixture() throws {
        let fixtureURL = sampleFixtureURL(named: "Showcase.md")
        let payload = try MarkdownDocumentRenderer().render(fileAt: fixtureURL)

        XCTAssertEqual(payload.tableOfContents.count, 5)
        XCTAssertEqual(payload.tableOfContents.first?.level, 1)
        XCTAssertEqual(
            payload.tableOfContents.dropFirst().map(\.level),
            [2, 2, 2, 2]
        )
    }

    private func sampleFixtureURL(named filename: String, file: StaticString = #filePath) -> URL {
        let testFile = URL(fileURLWithPath: String(describing: file))
        let repoRoot = testFile
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // MarkdownRendering/
            .deletingLastPathComponent() // repo root
        let url = repoRoot.appendingPathComponent("Fixtures").appendingPathComponent(filename)
        precondition(
            FileManager.default.fileExists(atPath: url.path),
            "Fixture not found at \(url.path) — did the test file or Fixtures/ directory move?"
        )
        return url
    }

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

    func testRenderWarningAlertHasBodyAfterTitleLine() throws {
        let payload = try renderDocument(
            """
            > [!WARNING] Read this first
            > Mind the gap.
            """
        ).payload
        let rendered = renderedTextStorage(from: payload.attributedContent)
        let s = rendered.string as NSString
        let titleLoc = s.range(of: "Read this first").location
        let bodyLoc = s.range(of: "Mind the gap.").location
        XCTAssertNotEqual(titleLoc, NSNotFound)
        XCTAssertNotEqual(bodyLoc, NSNotFound)
        XCTAssertLessThan(titleLoc, bodyLoc, "title must precede body in rendered output")
        // Ensure the body is not concatenated into the title; they should be on separate paragraphs.
        let titleEnd = titleLoc + ("Read this first" as NSString).length
        let between = s.substring(with: NSRange(location: titleEnd, length: bodyLoc - titleEnd))
        XCTAssertTrue(between.contains("\n"), "title and body must be separated by a newline; got '\(between)'")
    }

    func testRenderNoteAlertHeaderUsesTintAndTextBlock() throws {
        let payload = try renderDocument(
            """
            > [!NOTE]
            > Body.
            """
        ).payload

        let rendered = renderedTextStorage(from: payload.attributedContent)
        let nsString = rendered.string as NSString
        let headerRange = nsString.range(of: "Note")
        XCTAssertNotEqual(headerRange.location, NSNotFound)

        let color = rendered.attribute(.foregroundColor, at: headerRange.location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.systemBlue, "note header should use systemBlue tint")

        let style = rendered.attribute(.paragraphStyle, at: headerRange.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(style?.textBlocks.first, "header paragraph should carry a TintedBorderTextBlock")
    }

    func testRenderWarningAlertBodyCarriesTintedBlock() throws {
        let payload = try renderDocument(
            """
            > [!WARNING] Watch out
            > Body line.
            """
        ).payload

        let rendered = renderedTextStorage(from: payload.attributedContent)
        let bodyRange = (rendered.string as NSString).range(of: "Body line.")
        XCTAssertNotEqual(bodyRange.location, NSNotFound)

        let style = rendered.attribute(.paragraphStyle, at: bodyRange.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(style?.textBlocks.first, "body paragraph should carry a TintedBorderTextBlock")
    }

    func testRenderAlertWithNoBodyStillRenders() throws {
        let payload = try renderDocument("> [!TIP]").payload
        let s = payload.attributedContent.string
        XCTAssertTrue(s.contains("Tip"), "empty-body alert should still render its title")
        XCTAssertFalse(s.contains("[!TIP]"), "marker should be stripped even with no body")
    }

    func testRenderAlertWithWhitespaceOnlyCustomTitleFallsBackToDefault() throws {
        let source = "> [!CAUTION]   \n> Body."
        let payload = try renderDocument(source).payload
        let s = payload.attributedContent.string
        XCTAssertTrue(s.contains("Caution"), "should fall back to default title 'Caution'")
        XCTAssertTrue(s.contains("Body."))
    }

    func testRenderInlineFootnoteReferenceIsSuperscript() throws {
        let payload = try renderDocument(
            """
            Body text[^1].

            [^1]: First note.
            """
        ).payload

        let s = payload.attributedContent.string
        XCTAssertTrue(s.contains("Body text"), "body present")
        XCTAssertTrue(s.contains("¹"), "reference rendered as superscript numeric marker")
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

    func testRenderFootnoteReferencesInsideDefinitionBodyRenderLiteral() throws {
        let payload = try renderDocument(
            """
            Body[^1].

            [^1]: See also [^other] for context.
            [^other]: Other note.
            """
        ).payload

        let s = payload.attributedContent.string
        // Body reference is superscripted.
        XCTAssertTrue(s.contains("¹"), "body reference should be superscripted")
        // Reference inside the definition body remains literal — not substituted.
        // replaceFootnoteReferences only runs over cleanedLines (definitions stripped),
        // so [^other] inside the definition body text is never seen by that pass.
        XCTAssertTrue(s.contains("[^other]"), "ref inside definition body should NOT be superscripted")
        // [^other] is referenced only inside another definition's body. resolveFootnoteOrder
        // scans cleanedLines (definitions removed), so [^other] is never encountered there —
        // it gets no number and does NOT appear as a numbered section entry.
        XCTAssertFalse(s.contains("Other note."), "ref-less definition body should not render as a section entry")
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

        let leftHeaderRange = nsString.range(of: "Left")
        let centerHeaderRange = nsString.range(of: "Center")
        let rightHeaderRange = nsString.range(of: "Right")

        let leftHeaderStyle = rendered.attribute(.paragraphStyle, at: leftHeaderRange.location, effectiveRange: nil) as? NSParagraphStyle
        let centerHeaderStyle = rendered.attribute(.paragraphStyle, at: centerHeaderRange.location, effectiveRange: nil) as? NSParagraphStyle
        let rightHeaderStyle = rendered.attribute(.paragraphStyle, at: rightHeaderRange.location, effectiveRange: nil) as? NSParagraphStyle

        XCTAssertEqual(leftHeaderStyle?.alignment, .left, "header should share column alignment")
        XCTAssertEqual(centerHeaderStyle?.alignment, .center, "header should share column alignment")
        XCTAssertEqual(rightHeaderStyle?.alignment, .right, "header should share column alignment")
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
