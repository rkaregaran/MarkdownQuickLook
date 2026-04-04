import SwiftUI

@main
struct MarkdownQuickLookApp: App {
    init() {
        #if ENABLE_EXTENSION_CLEANUP
        DispatchQueue.global(qos: .utility).async {
            ExtensionCleanup.removeStaleExtensions()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            StatusView()
        }
        .windowResizability(.contentSize)
    }
}
