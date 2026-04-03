import Foundation

struct PreviewRequestTracker {
    private(set) var activeRequestID: UUID?

    var hasActiveRequest: Bool {
        activeRequestID != nil
    }

    mutating func beginRequest() -> UUID {
        let requestID = UUID()
        activeRequestID = requestID
        return requestID
    }

    func isActive(_ requestID: UUID) -> Bool {
        activeRequestID == requestID
    }

    @discardableResult
    mutating func finishRequest(_ requestID: UUID) -> Bool {
        guard activeRequestID == requestID else {
            return false
        }

        activeRequestID = nil
        return true
    }

    @discardableResult
    mutating func cancelRequest(_ requestID: UUID) -> Bool {
        finishRequest(requestID)
    }
}
