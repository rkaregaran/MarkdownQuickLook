import SwiftUI

@main
struct MarkdownQuickLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            StatusView(appState: AppState.shared)
        }
        .windowResizability(.contentSize)
    }
}
