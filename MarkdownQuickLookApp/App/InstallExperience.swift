import Foundation

struct InstallExperience: Equatable {
    enum State: Equatable {
        case installed
        case moveToApplications
    }

    let state: State
    let headline: String
    let bodyText: String
    let reassuranceText: String
    let caveatText: String
    let primaryActionTitle: String
    let stepsTitle: String
    let usageSteps: [String]

    static func current(
        for bundleURL: URL = Bundle.main.bundleURL,
        homeDirectoryPath: String = NSHomeDirectory()
    ) -> InstallExperience {
        let receiptPath = Bundle.main.bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt").path
        let isAppStore = FileManager.default.fileExists(atPath: receiptPath)

        if isAppStore || isInstalledInApplicationsFolder(bundleURL, homeDirectoryPath: homeDirectoryPath) {
            return InstallExperience(
                state: .installed,
                headline: "Markdown preview is installed.",
                bodyText: "The Quick Look extension is ready. This first launch is the only launch it needs.",
                reassuranceText: "You can close this app now. You do not need to keep it open for Finder previews.",
                caveatText: "If previews don't appear, go to System Settings > General > Login Items & Extensions > Quick Look and make sure Markdown Quick Look Preview is enabled.",
                primaryActionTitle: "Close App",
                stepsTitle: "How to use it",
                usageSteps: [
                    "Select a Markdown file in Finder.",
                    "Press Space to preview it with Quick Look."
                ]
            )
        }

        return InstallExperience(
            state: .moveToApplications,
            headline: "Move the app to /Applications first.",
            bodyText: "MarkdownQuickLook should be moved to /Applications before its first real launch so Finder registers the Quick Look extension from its permanent location.",
            reassuranceText: "After moving it, open it once, then click Close App. You will not need to open it again for normal Finder previews.",
            caveatText: "If previews don't appear, go to System Settings > General > Login Items & Extensions > Quick Look and make sure Markdown Quick Look Preview is enabled.",
            primaryActionTitle: "Close App",
            stepsTitle: "Finish setup",
            usageSteps: [
                "Drag MarkdownQuickLook.app into /Applications.",
                "Open it once from /Applications.",
                "Click Close App."
            ]
        )
    }

    private static func isInstalledInApplicationsFolder(
        _ bundleURL: URL,
        homeDirectoryPath: String
    ) -> Bool {
        let bundlePath = bundleURL.standardizedFileURL.path
        let systemApplicationsPath = "/Applications/"
        let userApplicationsPath = URL(fileURLWithPath: homeDirectoryPath, isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .path + "/"

        return bundlePath.hasPrefix(systemApplicationsPath)
            || bundlePath.hasPrefix(userApplicationsPath)
    }
}
