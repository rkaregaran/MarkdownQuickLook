import MarkdownRendering
import XCTest

@MainActor
final class TableOfContentsViewModelTests: XCTestCase {
    func testDisplayableAnchorsKeepsLevelsOneThroughThree() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([
            anchor(level: 1),
            anchor(level: 2),
            anchor(level: 3),
            anchor(level: 4),
            anchor(level: 5)
        ])

        XCTAssertEqual(viewModel.displayableAnchors.map(\.level), [1, 2, 3])
    }

    func testVisibilityForEmptyHeadings() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([])

        XCTAssertFalse(viewModel.shouldShowSidebar)
        XCTAssertFalse(viewModel.shouldShowExpandStrip)
    }

    func testVisibilityForSingleHeading() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1)])

        XCTAssertFalse(viewModel.shouldShowSidebar)
        XCTAssertFalse(viewModel.shouldShowExpandStrip)
    }

    func testVisibilityWhenExpandedAndCollapsed() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])

        XCTAssertTrue(viewModel.shouldShowSidebar)
        XCTAssertFalse(viewModel.shouldShowExpandStrip)

        viewModel.collapsed = true

        XCTAssertFalse(viewModel.shouldShowSidebar)
        XCTAssertTrue(viewModel.shouldShowExpandStrip)
    }

    func testVisibilityIgnoresLevelsBelowThree() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 4), anchor(level: 5), anchor(level: 6)])

        XCTAssertFalse(viewModel.shouldShowSidebar)
        XCTAssertFalse(viewModel.shouldShowExpandStrip)
    }

    func testActiveAnchorIndexClampsWhenAnchorsShrink() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2), anchor(level: 3)])
        viewModel.activeAnchorIndex = 2

        viewModel.setAnchors([anchor(level: 1)])

        XCTAssertNil(viewModel.activeAnchorIndex)
    }

    func testRequestScrollInvokesHandlerAndUpdatesActiveIndex() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])

        var receivedIndex: Int?
        viewModel.scrollHandler = { receivedIndex = $0 }

        viewModel.requestScroll(to: 1)

        XCTAssertEqual(receivedIndex, 1)
        XCTAssertEqual(viewModel.activeAnchorIndex, 1)
    }

    func testRequestScrollIgnoresOutOfBoundsIndex() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])

        var handlerCalls = 0
        viewModel.scrollHandler = { _ in handlerCalls += 1 }

        viewModel.requestScroll(to: 5)

        XCTAssertEqual(handlerCalls, 0)
        XCTAssertNil(viewModel.activeAnchorIndex)
    }

    func testRequestScrollWithNilHandlerStillUpdatesActiveIndex() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])

        XCTAssertNil(viewModel.scrollHandler)
        viewModel.requestScroll(to: 1)

        XCTAssertEqual(viewModel.activeAnchorIndex, 1)
    }

    func testSetAnchorsClearsActiveIndexAtEqualBoundary() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])
        viewModel.activeAnchorIndex = 1

        // Shrink so previous active index (1) equals new count (1) -> first out-of-bounds.
        viewModel.setAnchors([anchor(level: 1)])

        XCTAssertNil(viewModel.activeAnchorIndex)
    }

    private func anchor(level: Int, location: Int = 0) -> HeadingAnchor {
        HeadingAnchor(level: level, text: "H\(level)", range: NSRange(location: location, length: 0))
    }
}
