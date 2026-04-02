import AppKit
import XCTest
@testable import MarkdownRendering

final class MarkdownDocumentRendererTests: XCTestCase {
    func testRenderKeepsWrappedParagraphLinesTogether() throws {
        let url = try temporaryMarkdownFile(
            """
            First line of a paragraph
            wrapped continuation

            Second paragraph
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try MarkdownDocumentRenderer().render(fileAt: url)

        XCTAssertEqual(payload.title, url.lastPathComponent)
        XCTAssertEqual(
            payload.attributedContent.string,
            "First line of a paragraph wrapped continuation\n\nSecond paragraph"
        )
    }

    func testRenderKeepsMultiLineQuoteTogether() throws {
        let url = try temporaryMarkdownFile(
            """
            > First quote line
            > second quote line

            After quote
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try MarkdownDocumentRenderer().render(fileAt: url)

        XCTAssertEqual(
            payload.attributedContent.string,
            "│ First quote line second quote line\n\nAfter quote"
        )
    }

    func testRenderKeepsMultiLineListItemTogether() throws {
        let url = try temporaryMarkdownFile(
            """
            - First list line
              continuation line
            - Second item
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try MarkdownDocumentRenderer().render(fileAt: url)

        XCTAssertEqual(
            payload.attributedContent.string,
            "• First list line continuation line\n• Second item"
        )
    }

    func testRenderPreservesFencedCodeBlockContentAndStyle() throws {
        let url = try temporaryMarkdownFile(
            """
            Before

            ```
            let value = 1
            let doubled = value * 2
            ```

            After
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try MarkdownDocumentRenderer().render(fileAt: url)
        let nsString = payload.attributedContent.string as NSString
        let codeRange = nsString.range(of: "let value = 1\nlet doubled = value * 2")
        let font = payload.attributedContent.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont

        XCTAssertNotEqual(codeRange.location, NSNotFound)
        XCTAssertEqual(
            payload.attributedContent.string,
            "Before\n\nlet value = 1\nlet doubled = value * 2\n\nAfter"
        )
        XCTAssertTrue(font?.isFixedPitch == true)
    }

    func testRenderPreservesHeadingInlineLinkAttributes() throws {
        let url = try temporaryMarkdownFile("# Heading with [OpenAI](https://openai.com)")
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try MarkdownDocumentRenderer().render(fileAt: url)
        let nsString = payload.attributedContent.string as NSString
        let range = nsString.range(of: "OpenAI")
        let link = payload.attributedContent.attribute(.link, at: range.location, effectiveRange: nil) as? URL

        XCTAssertEqual(link, URL(string: "https://openai.com"))
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
}
