enum InstallExperience {
    static let primaryActionTitle = "Close App"

    static let bodyText = """
    This app is designed to be launched once, then live in /Applications like a normal Mac app.
    """

    static let usageSteps = [
        "Select a Markdown file in Finder.",
        "Press Space to preview it with Quick Look."
    ]
}
