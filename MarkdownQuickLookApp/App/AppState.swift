import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var openedFileURLs: [URL] = []

    func recordOpenedFileURLs(_ urls: [URL]) {
        openedFileURLs.append(contentsOf: urls)
    }
}
