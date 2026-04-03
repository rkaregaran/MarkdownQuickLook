import AppKit
import MarkdownRendering
import XCTest

@MainActor
final class PreviewViewControllerTests: XCTestCase {
    func testPreparePreviewDisplaysRenderedContent() async throws {
        let url = try makeMarkdownFile(named: "Rendered.md", contents: "# Rendered")
        let document = try MarkdownDocumentRenderer().prepareDocument(fileAt: url)
        let controller = PreviewViewController(
            prepareDocumentResultProvider: { _ in .prepared(document) },
            renderProvider: { document, _ in
                MarkdownRenderPayload(
                    title: document.title,
                    attributedContent: NSAttributedString(string: "Rendered content")
                )
            }
        )

        controller.loadViewIfNeeded()
        XCTAssertEqual(controller.preferredContentSize, PreviewSizing.loadingPreferredContentSize)

        try await controller.preparePreviewOfFile(at: url)

        let rootView = controller.testingCurrentRootView
        XCTAssertEqual(rootView.title, "Rendered.md")
        XCTAssertEqual(rootView.attributedContent?.string, "Rendered content")
        XCTAssertNil(rootView.message)
        XCTAssertEqual(
            controller.preferredContentSize,
            PreviewSizing.preferredContentSize(forRenderedText: "Rendered content")
        )
    }

    func testPreparePreviewMapsRendererErrorsToMessageState() async throws {
        let url = try makeMarkdownFile(named: "Empty.md", contents: "# Placeholder")
        let controller = PreviewViewController(
            prepareDocumentResultProvider: { _ in .rendererError(.emptyDocument(url)) },
            renderProvider: { _, _ in
                XCTFail("Render should not run for renderer errors.")
                return MarkdownRenderPayload(title: "", attributedContent: NSAttributedString())
            }
        )

        controller.loadViewIfNeeded()
        XCTAssertEqual(controller.preferredContentSize, PreviewSizing.loadingPreferredContentSize)

        try await controller.preparePreviewOfFile(at: url)

        let rootView = controller.testingCurrentRootView
        XCTAssertEqual(rootView.title, "Empty.md")
        XCTAssertEqual(rootView.message, MarkdownDocumentRendererError.emptyDocument(url).errorDescription)
        XCTAssertNil(rootView.attributedContent)
        XCTAssertEqual(controller.preferredContentSize, PreviewSizing.errorPreferredContentSize)
    }

    func testStaleRequestDoesNotOverrideNewerPreviewState() async throws {
        let slowURL = try makeMarkdownFile(named: "Slow.md", contents: "# Slow")
        let fastURL = try makeMarkdownFile(named: "Fast.md", contents: "# Fast")
        let slowDocument = try MarkdownDocumentRenderer().prepareDocument(fileAt: slowURL)
        let fastDocument = try MarkdownDocumentRenderer().prepareDocument(fileAt: fastURL)
        let controller = PreviewViewController(
            prepareDocumentResultProvider: { url in
                if url == slowURL {
                    Thread.sleep(forTimeInterval: 0.05)
                    return .prepared(slowDocument)
                }

                return .prepared(fastDocument)
            },
            renderProvider: { document, _ in
                MarkdownRenderPayload(
                    title: document.title,
                    attributedContent: NSAttributedString(string: document.title)
                )
            }
        )

        controller.loadViewIfNeeded()

        let staleTask = Task {
            try await controller.preparePreviewOfFile(at: slowURL)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        try await controller.preparePreviewOfFile(at: fastURL)
        _ = await staleTask.result

        let rootView = controller.testingCurrentRootView
        XCTAssertEqual(rootView.title, "Fast.md")
        XCTAssertEqual(rootView.attributedContent?.string, "Fast.md")
    }

    func testCancelledPreviewKeepsLoadingStateAndClearsActiveRequest() async throws {
        let url = try makeMarkdownFile(named: "Cancelled.md", contents: "# Cancelled")
        let document = try MarkdownDocumentRenderer().prepareDocument(fileAt: url)
        let controller = PreviewViewController(
            prepareDocumentResultProvider: { _ in
                Thread.sleep(forTimeInterval: 0.05)
                return .prepared(document)
            },
            renderProvider: { document, _ in
                MarkdownRenderPayload(
                    title: document.title,
                    attributedContent: NSAttributedString(string: document.title)
                )
            }
        )

        controller.loadViewIfNeeded()

        let task = Task {
            try await controller.preparePreviewOfFile(at: url)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        _ = await task.result
        try await Task.sleep(nanoseconds: 60_000_000)

        let rootView = controller.testingCurrentRootView
        XCTAssertEqual(rootView.title, "Cancelled.md")
        XCTAssertEqual(rootView.message, "Loading preview...")
        XCTAssertNil(rootView.attributedContent)
        XCTAssertFalse(controller.testingHasActiveRequest)
    }

    private func makeMarkdownFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
