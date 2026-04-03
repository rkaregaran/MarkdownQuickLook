import XCTest

final class InstallExperienceTests: XCTestCase {
    func testPrimaryActionTitleMatchesReleaseCopy() {
        XCTAssertEqual(InstallExperience.primaryActionTitle, "Close App")
    }

    func testBodyTextExplainsTheInstallExperience() {
        XCTAssertTrue(InstallExperience.bodyText.contains("launched once"))
        XCTAssertTrue(InstallExperience.bodyText.contains("/Applications"))
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
