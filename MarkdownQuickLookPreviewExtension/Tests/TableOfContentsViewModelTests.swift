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

    func testShouldShowSidebarStaysFalseWhenFeatureFlagDisabled() {
        let viewModel = TableOfContentsViewModel(featureEnabled: false)
        viewModel.setAnchors(Array(repeating: anchor(level: 2), count: 20))
        XCTAssertFalse(viewModel.shouldShowSidebar, "Flag off must override any heading count")
    }

    func testShouldShowSidebarForEmptyHeadingsWithFlagEnabled() {
        let viewModel = TableOfContentsViewModel(featureEnabled: true)
        viewModel.setAnchors([])
        XCTAssertFalse(viewModel.shouldShowSidebar)
    }

    func testShouldShowSidebarForNineHeadingsWithFlagEnabled() {
        let viewModel = TableOfContentsViewModel(featureEnabled: true)
        viewModel.setAnchors(Array(repeating: anchor(level: 2), count: 9))
        XCTAssertFalse(viewModel.shouldShowSidebar, "Below threshold (9 < 10)")
    }

    func testShouldShowSidebarFlipsAtTenDisplayableHeadingsWithFlagEnabled() {
        let viewModel = TableOfContentsViewModel(featureEnabled: true)
        viewModel.setAnchors(Array(repeating: anchor(level: 2), count: 10))
        XCTAssertTrue(viewModel.shouldShowSidebar, "At threshold (10 >= 10)")
    }

    func testShouldShowSidebarIgnoresLevelsBelowThreeWithFlagEnabled() {
        let viewModel = TableOfContentsViewModel(featureEnabled: true)
        viewModel.setAnchors(Array(repeating: anchor(level: 4), count: 20))
        XCTAssertFalse(viewModel.shouldShowSidebar, "h4+ are filtered out of displayableAnchors")
    }

    func testActiveAnchorIndexClampsWhenAnchorsShrink() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2), anchor(level: 3)])
        viewModel.activeAnchorIndex = 2

        viewModel.setAnchors([anchor(level: 1)])

        XCTAssertNil(viewModel.activeAnchorIndex)
    }

    func testSetAnchorsClearsActiveIndexAtEqualBoundary() {
        let viewModel = TableOfContentsViewModel()
        viewModel.setAnchors([anchor(level: 1), anchor(level: 2)])
        viewModel.activeAnchorIndex = 1

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

    func testActiveAnchorIndexIsNilForEmptyAnchors() {
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 0,
            anchorYPositions: []
        )
        XCTAssertNil(result)
    }

    func testActiveAnchorIndexHighlightsFirstWhenScrolledAboveAllAnchors() {
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 0,
            anchorYPositions: [100, 200, 300]
        )
        XCTAssertEqual(result, 0)
    }

    func testActiveAnchorIndexPicksLastAnchorAtOrAboveThreshold() {
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 250,
            anchorYPositions: [100, 200, 300]
        )
        XCTAssertEqual(result, 1)
    }

    func testActiveAnchorIndexUsesActivationOffset() {
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 90,
            anchorYPositions: [100, 300]
        )
        XCTAssertEqual(result, 0)
    }

    func testActiveAnchorIndexPastLastAnchorPicksLast() {
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 9_999,
            anchorYPositions: [100, 200, 300]
        )
        XCTAssertEqual(result, 2)
    }

    func testActiveAnchorIndexExactBoundarySelectsThatAnchor() {
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 76,
            anchorYPositions: [50, 100, 200]
        )
        XCTAssertEqual(result, 1)
    }

    func testActiveAnchorIndexOnePastBoundaryFallsBackToPrevious() {
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 76,
            anchorYPositions: [50, 101, 200]
        )
        XCTAssertEqual(result, 0)
    }

    private func anchor(level: Int, location: Int = 0) -> HeadingAnchor {
        HeadingAnchor(level: level, text: "H\(level)", range: NSRange(location: location, length: 0))
    }
}
