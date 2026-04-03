import XCTest

final class InstallExperienceTests: XCTestCase {
    func testHeadlineMatchesReleaseCopy() {
        XCTAssertEqual(InstallExperience.headline, "Markdown preview is installed.")
    }

    func testPrimaryActionTitleMatchesReleaseCopy() {
        XCTAssertEqual(InstallExperience.primaryActionTitle, "Close App")
    }

    func testBodyTextExplainsTheInstallExperience() {
        XCTAssertEqual(
            InstallExperience.bodyText,
            "MarkdownQuickLook has registered its Quick Look extension. After moving the app to /Applications, it only needs to be launched once."
        )
    }

    func testReassuranceTextMatchesReleaseCopy() {
        XCTAssertEqual(
            InstallExperience.reassuranceText,
            "You can close this app now. You do not need to keep it open for Finder previews."
        )
    }

    func testCaveatTextMatchesReleaseCopy() {
        XCTAssertEqual(
            InstallExperience.caveatText,
            "Standard .md preview remains best-effort. Some macOS versions may still prefer Apple's built-in plain-text preview."
        )
    }

    func testUsageStepsMatchTheExpectedFinderInstructions() {
        XCTAssertEqual(
            InstallExperience.usageSteps,
            [
                "Select a Markdown file in Finder.",
                "Press Space to preview it with Quick Look."
            ]
        )
    }
}
