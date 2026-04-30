import XCTest
@testable import MarkdownRendering

final class SmokeTests: XCTestCase {
    func testRendererInitializes() {
        XCTAssertNotNil(MarkdownDocumentRenderer())
    }

    func testPerformanceInstrumentationCanBeCalledFromTests() {
        let interval = MarkdownPerformanceInstrumentation.begin("test.instrumentation")
        MarkdownPerformanceInstrumentation.event("test.instrumentation.event")
        MarkdownPerformanceInstrumentation.debug("test instrumentation debug line")
        MarkdownPerformanceInstrumentation.end(interval)
    }
}
