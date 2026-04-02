import XCTest

final class PreviewRequestTrackerTests: XCTestCase {
    func testNewerRequestMakesOlderResultStale() {
        var tracker = PreviewRequestTracker()

        let firstRequestID = tracker.beginRequest()
        let secondRequestID = tracker.beginRequest()

        XCTAssertFalse(tracker.isActive(firstRequestID))
        XCTAssertTrue(tracker.isActive(secondRequestID))
    }

    func testCompletingOlderRequestDoesNotClearNewerRequest() {
        var tracker = PreviewRequestTracker()

        let firstRequestID = tracker.beginRequest()
        let secondRequestID = tracker.beginRequest()

        XCTAssertFalse(tracker.finishRequest(firstRequestID))
        XCTAssertTrue(tracker.isActive(secondRequestID))
        XCTAssertTrue(tracker.finishRequest(secondRequestID))
        XCTAssertNil(tracker.activeRequestID)
    }

    func testCancelRequestClearsCurrentRequest() {
        var tracker = PreviewRequestTracker()

        let requestID = tracker.beginRequest()

        XCTAssertTrue(tracker.cancelRequest(requestID))
        XCTAssertNil(tracker.activeRequestID)
        XCTAssertFalse(tracker.isActive(requestID))
    }
}
