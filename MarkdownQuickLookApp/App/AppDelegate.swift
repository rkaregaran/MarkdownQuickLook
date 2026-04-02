import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        AppState.shared.recordOpenedFileURLs(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        AppState.shared.recordOpenedFileURLs([URL(fileURLWithPath: filename)])
        return true
    }
}
