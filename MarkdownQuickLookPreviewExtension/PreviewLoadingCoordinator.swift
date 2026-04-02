import Foundation

@MainActor
final class PreviewLoadingCoordinator<Output> {
    private var requestTracker = PreviewRequestTracker()
    private(set) var activeTask: Task<Output, Never>?

    func beginRequest(
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () -> Output
    ) -> (requestID: UUID, task: Task<Output, Never>) {
        let requestID = requestTracker.beginRequest()
        activeTask?.cancel()

        let task = Task.detached(priority: priority, operation: operation)
        activeTask = task

        return (requestID, task)
    }

    @discardableResult
    func finishRequest(_ requestID: UUID) -> Bool {
        guard requestTracker.finishRequest(requestID) else {
            return false
        }

        activeTask = nil
        return true
    }

    @discardableResult
    func cancelRequest(_ requestID: UUID, task: Task<Output, Never>? = nil) -> Bool {
        (task ?? activeTask)?.cancel()

        guard requestTracker.cancelRequest(requestID) else {
            return false
        }

        activeTask = nil
        return true
    }
}
