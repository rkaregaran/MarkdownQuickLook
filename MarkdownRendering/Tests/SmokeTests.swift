import XCTest
@testable import MarkdownRendering

final class SmokeTests: XCTestCase {
    func testRendererInitializes() {
        XCTAssertNotNil(MarkdownDocumentRenderer())
    }
}
