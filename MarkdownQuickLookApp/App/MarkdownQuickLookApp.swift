import SwiftUI

@main
struct MarkdownQuickLookApp: App {
    init() {
        DispatchQueue.global(qos: .utility).async {
            ExtensionCleanup.removeStaleExtensions()
        }
    }

    var body: some Scene {
        WindowGroup {
            StatusView()
        }
        .windowResizability(.contentSize)
    }
}
