#if ENABLE_EXTENSION_CLEANUP
import Foundation

enum ExtensionCleanup {

    private static let extensionBundleID = "com.rzkr.MarkdownQuickLook.app.preview"
    private static let extensionName = "MarkdownQuickLookPreviewExtension.appex"

    /// Finds all registered copies of our Quick Look extension on disk and
    /// unregisters any that live outside the currently-running app bundle.
    /// Call from a background queue — this blocks while subprocesses run.
    static func removeStaleExtensions() {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else { return }
        let currentExtensionPath = plugInsURL
            .appendingPathComponent(extensionName).path

        let allPaths = findExtensionPaths()
        let stalePaths = allPaths.filter { $0 != currentExtensionPath }

        for path in stalePaths {
            run("/usr/bin/pluginkit", arguments: ["-r", path])
        }

        // Ensure the current copy is registered from its new location.
        run("/usr/bin/pluginkit", arguments: ["-a", currentExtensionPath])
    }

    // MARK: - Private

    private static func findExtensionPaths() -> [String] {
        guard let output = run("/usr/bin/pluginkit", arguments: [
            "-mDvvv", "-i", extensionBundleID
        ]) else {
            return []
        }
        // Parse "Path = /some/path" lines from pluginkit verbose output.
        return output
            .components(separatedBy: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("Path = ") else { return nil }
                return String(trimmed.dropFirst("Path = ".count))
            }
    }

    @discardableResult
    private static func run(
        _ executablePath: String,
        arguments: [String]
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
#endif
