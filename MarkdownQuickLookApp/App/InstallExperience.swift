enum InstallExperience {
    static let headline = "Markdown preview is installed."

    static let primaryActionTitle = "Close App"

    static let bodyText = """
    MarkdownQuickLook has registered its Quick Look extension. After moving the app to /Applications, it only needs to be launched once.
    """

    static let reassuranceText = """
    You can close this app now. You do not need to keep it open for Finder previews.
    """

    static let caveatText = """
    Standard .md preview remains best-effort. Some macOS versions may still prefer Apple's built-in plain-text preview.
    """

    static let usageSteps = [
        "Select a Markdown file in Finder.",
        "Press Space to preview it with Quick Look."
    ]
}
