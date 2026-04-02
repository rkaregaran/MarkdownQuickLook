import XCTest

final class PreviewRequestTrackerTests: XCTestCase {
    func testBeginRequestSupersedesEarlierRequest() {
        var tracker = PreviewRequestTracker()

        let firstRequestID = tracker.beginRequest()
        let secondRequestID = tracker.beginRequest()

        XCTAssertFalse(tracker.isActive(firstRequestID))
        XCTAssertTrue(tracker.isActive(secondRequestID))
    }

    func testFinishRequestIgnoresStaleRequest() {
        var tracker = PreviewRequestTracker()

        let firstRequestID = tracker.beginRequest()
        let secondRequestID = tracker.beginRequest()

        XCTAssertFalse(tracker.finishRequest(firstRequestID))
        XCTAssertTrue(tracker.isActive(secondRequestID))
        XCTAssertTrue(tracker.finishRequest(secondRequestID))
        XCTAssertNil(tracker.activeRequestID)
    }
}
