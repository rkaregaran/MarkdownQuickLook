import Foundation

struct PreviewRequestTracker {
    private(set) var activeRequestID: UUID?

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
}
