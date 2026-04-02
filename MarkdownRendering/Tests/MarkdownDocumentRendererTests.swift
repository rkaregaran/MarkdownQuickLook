import XCTest
@testable import MarkdownRendering

final class MarkdownDocumentRendererTests: XCTestCase {
    func testRenderFormatsHeadingsListsAndQuotes() throws {
        let url = try temporaryMarkdownFile(
            """
            # Title

            Paragraph with `code`.

            - First item
            > Quoted line
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try MarkdownDocumentRenderer().render(fileAt: url)

        XCTAssertEqual(payload.title, url.lastPathComponent)
        XCTAssertTrue(payload.attributedContent.string.contains("Title"))
        XCTAssertTrue(payload.attributedContent.string.contains("Paragraph with code."))
        XCTAssertTrue(payload.attributedContent.string.contains("• First item"))
        XCTAssertTrue(payload.attributedContent.string.contains("│ Quoted line"))
    }

    func testRenderPreservesLinkAttribute() throws {
        let url = try temporaryMarkdownFile("[OpenAI](https://openai.com)")
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
