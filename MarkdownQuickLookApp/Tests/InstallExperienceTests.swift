import XCTest

final class InstallExperienceTests: XCTestCase {
    private let homeDirectoryPath = "/Users/tester"

    func testInstalledExperienceShowsSuccessCopy() {
        let experience = InstallExperience.current(
            for: URL(fileURLWithPath: "/Applications/MarkdownQuickLook.app"),
            homeDirectoryPath: homeDirectoryPath
        )

        XCTAssertEqual(experience.state, .installed)
        XCTAssertEqual(experience.headline, "Markdown preview is installed.")
        XCTAssertEqual(
            experience.bodyText,
            "The Quick Look extension is ready. This first launch is the only launch it needs."
        )
        XCTAssertEqual(
            experience.reassuranceText,
            "You can close this app now. You do not need to keep it open for Finder previews."
        )
        XCTAssertEqual(experience.stepsTitle, "How to use it")
        XCTAssertEqual(
            experience.usageSteps,
            [
                "Select a Markdown file in Finder.",
                "Press Space to preview it with Quick Look."
            ]
        )
    }

    func testPrimaryActionTitleMatchesReleaseCopy() {
        let experience = InstallExperience.current(
            for: URL(fileURLWithPath: "/Applications/MarkdownQuickLook.app"),
            homeDirectoryPath: homeDirectoryPath
        )

        XCTAssertEqual(experience.primaryActionTitle, "Close App")
    }

    func testMoveFirstExperiencePromptsForApplicationsInstall() {
        let experience = InstallExperience.current(
            for: URL(fileURLWithPath: "/Users/tester/Downloads/MarkdownQuickLook.app"),
            homeDirectoryPath: homeDirectoryPath
        )

        XCTAssertEqual(experience.state, .moveToApplications)
        XCTAssertEqual(experience.headline, "Move the app to /Applications first.")
        XCTAssertEqual(
            experience.bodyText,
            "MarkdownQuickLook should be moved to /Applications before its first real launch so Finder registers the Quick Look extension from its permanent location."
        )
        XCTAssertEqual(
            experience.reassuranceText,
            "After moving it, open it once, then click Close App. You will not need to open it again for normal Finder previews."
        )
        XCTAssertEqual(experience.stepsTitle, "Finish setup")
        XCTAssertEqual(
            experience.usageSteps,
            [
                "Drag MarkdownQuickLook.app into /Applications.",
                "Open it once from /Applications.",
                "Click Close App."
            ]
        )
    }

    func testCaveatTextMatchesReleaseCopy() {
        let experience = InstallExperience.current(
            for: URL(fileURLWithPath: "/Applications/MarkdownQuickLook.app"),
            homeDirectoryPath: homeDirectoryPath
        )

        XCTAssertEqual(
            experience.caveatText,
            "If previews don't appear, go to System Settings > General > Login Items & Extensions > Quick Look and make sure Markdown Quick Look Preview is enabled."
        )
    }
}
