import Foundation

public struct MarkdownRenderPayload {
    public let title: String
    public let attributedContent: NSAttributedString

    public init(title: String, attributedContent: NSAttributedString) {
        self.title = title
        self.attributedContent = attributedContent
    }
}

public enum MarkdownDocumentRendererError: Error, Equatable {
    case unreadableFile(URL)
    case emptyDocument(URL)
}

public final class MarkdownDocumentRenderer {
    public init() {}

    public func render(fileAt url: URL) throws -> MarkdownRenderPayload {
        MarkdownRenderPayload(
            title: url.lastPathComponent,
            attributedContent: NSAttributedString(string: "Renderer not implemented yet.")
        )
    }
}
