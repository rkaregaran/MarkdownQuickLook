import XCTest

@MainActor
final class PreviewLoadingCoordinatorTests: XCTestCase {
    func testBeginningNewRequestCancelsPreviousTaskAndRejectsStaleCompletion() {
        let coordinator = PreviewLoadingCoordinator<Int>()

        let firstRequest = coordinator.beginRequest {
            1
        }
        let secondRequest = coordinator.beginRequest {
            2
        }

        XCTAssertTrue(firstRequest.task.isCancelled)
        XCTAssertFalse(coordinator.finishRequest(firstRequest.requestID))
        XCTAssertTrue(coordinator.finishRequest(secondRequest.requestID))
    }

    func testCancelRequestCancelsTaskAndClearsActiveState() {
        let coordinator = PreviewLoadingCoordinator<Int>()

        let request = coordinator.beginRequest {
            1
        }

        XCTAssertTrue(coordinator.cancelRequest(request.requestID, task: request.task))
        XCTAssertTrue(request.task.isCancelled)
        XCTAssertFalse(coordinator.finishRequest(request.requestID))
    }
}
