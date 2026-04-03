import AppKit
import XCTest

@MainActor
final class PreviewSizingTests: XCTestCase {
    func testLoadingSize() {
        XCTAssertEqual(
            PreviewSizing.loadingPreferredContentSize,
            CGSize(width: 900, height: 800)
        )
    }

    func testShortContentUsesBaseHeight() {
        XCTAssertEqual(
            PreviewSizing.preferredContentSize(forRenderedText: "Short content"),
            CGSize(width: 900, height: 900)
        )
    }

    func testLongerContentRequestsTallerHeight() {
        let renderedText = Array(repeating: "Line", count: 35).joined(separator: "\n")

        XCTAssertEqual(
            PreviewSizing.preferredContentSize(forRenderedText: renderedText),
            CGSize(width: 900, height: 1120)
        )
    }

    func testVeryLongContentCapsHeight() {
        let renderedText = Array(repeating: "Line", count: 100).joined(separator: "\n")

        XCTAssertEqual(
            PreviewSizing.preferredContentSize(forRenderedText: renderedText),
            CGSize(width: 900, height: 1400)
        )
    }
}
