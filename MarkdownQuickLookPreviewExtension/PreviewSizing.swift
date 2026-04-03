import AppKit

enum PreviewSizing {
    static let loadingPreferredContentSize = CGSize(width: 900, height: 800)
    static let errorPreferredContentSize = CGSize(width: 900, height: 800)

    private static let renderedWidth: CGFloat = 900
    private static let renderedBaseHeight: CGFloat = 900
    private static let renderedMaximumHeight: CGFloat = 1400
    private static let renderedLineThreshold = 24
    private static let renderedHeightPerAdditionalLine: CGFloat = 20

    static func preferredContentSize(forRenderedText renderedText: String) -> CGSize {
        let lineCount = max(1, renderedText.split(separator: "\n", omittingEmptySubsequences: false).count)
        let additionalLines = max(0, lineCount - renderedLineThreshold)
        let height = min(
            renderedMaximumHeight,
            renderedBaseHeight + (CGFloat(additionalLines) * renderedHeightPerAdditionalLine)
        )

        return CGSize(width: renderedWidth, height: height)
    }
}
