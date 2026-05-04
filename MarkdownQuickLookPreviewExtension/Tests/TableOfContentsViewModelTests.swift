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
        let suite = "test.toc.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Failed to create test UserDefaults suite")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let viewModel = TableOfContentsViewModel(defaults: defaults)
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

    func testCollapsedFlagPersistsThroughInjectedDefaults() {
        let suite = "test.toc.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Failed to create test UserDefaults suite")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let first = TableOfContentsViewModel(defaults: defaults)
        first.collapsed = true

        let second = TableOfContentsViewModel(defaults: defaults)
        XCTAssertTrue(second.collapsed)
    }

    func testCollapsedFlagDefaultsToFalseInFreshDefaults() {
        let suite = "test.toc.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Failed to create test UserDefaults suite")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let viewModel = TableOfContentsViewModel(defaults: defaults)
        XCTAssertFalse(viewModel.collapsed)
    }

    func testCollapsedNoOpAssignmentDoesNotOverwriteDefaults() {
        let suite = "test.toc.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Failed to create test UserDefaults suite")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let viewModel = TableOfContentsViewModel(defaults: defaults)
        XCTAssertFalse(viewModel.collapsed)

        // Inject a value out-of-band that disagrees with the view model's in-memory state,
        // then assign the same value the view model already holds. The didSet guard
        // should short-circuit so the out-of-band value is preserved.
        defaults.set(true, forKey: TableOfContentsViewModel.collapsedDefaultsKey)
        viewModel.collapsed = false

        XCTAssertTrue(defaults.bool(forKey: TableOfContentsViewModel.collapsedDefaultsKey))
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
        // visibleTop = 90, threshold = 90 + 24 = 114; anchor at 100 is "current".
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
        // cutoff = 76 + 24 = 100; anchor[1] sits exactly at 100, so <= picks it.
        let result = TableOfContentsViewModel.computeActiveAnchorIndex(
            visibleTop: 76,
            anchorYPositions: [50, 100, 200]
        )
        XCTAssertEqual(result, 1)
    }

    func testActiveAnchorIndexOnePastBoundaryFallsBackToPrevious() {
        // cutoff = 76 + 24 = 100; anchor[1] at 101 is one past the inclusive threshold,
        // so anchor[0] still wins. Catches a regression from <= to <.
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
