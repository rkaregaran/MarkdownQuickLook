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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Markdown Quick Look") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: aboutOptions)
                }
            }
        }
    }

    private var aboutOptions: [NSApplication.AboutPanelOptionKey: Any] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        return [
            .applicationName: "Markdown Quick Look",
            .applicationVersion: version,
            .version: build,
            .credits: NSAttributedString(
                string: "A macOS Quick Look extension for previewing Markdown files in Finder.\n\nhttps://github.com/rkaregaran/MarkdownQuickLook",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        ]
    }
}
