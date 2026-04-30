import AppKit
import MarkdownRendering
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let maximumSize = request.maximumSize
        let scale = request.scale
        let requestInterval = MarkdownPerformanceInstrumentation.begin("thumbnail.request")

        handler(QLThumbnailReply(contextSize: maximumSize, drawing: { context -> Bool in
            defer { MarkdownPerformanceInstrumentation.end(requestInterval) }

            let renderer = MarkdownDocumentRenderer()

            let prepareInterval = MarkdownPerformanceInstrumentation.begin("thumbnail.prepare")
            let document: MarkdownPreparedDocument
            do {
                defer { MarkdownPerformanceInstrumentation.end(prepareInterval) }
                document = try renderer.prepareDocument(fileAt: request.fileURL)
            } catch {
                MarkdownPerformanceInstrumentation.event("thumbnail.failure")
                return false
            }

            let renderInterval = MarkdownPerformanceInstrumentation.begin("thumbnail.render")
            defer { MarkdownPerformanceInstrumentation.end(renderInterval) }
            let payload = DispatchQueue.main.sync {
                renderer.render(document: document)
            }

            let attributed = payload.attributedContent

            let drawInterval = MarkdownPerformanceInstrumentation.begin("thumbnail.draw")
            defer { MarkdownPerformanceInstrumentation.end(drawInterval) }

            // Set up drawing area with padding.
            let padding: CGFloat = 8
            let drawRect = CGRect(
                x: padding,
                y: padding,
                width: maximumSize.width - padding * 2,
                height: maximumSize.height - padding * 2
            )

            // Draw background.
            let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
            let previousContext = NSGraphicsContext.current
            NSGraphicsContext.current = nsContext
            defer { NSGraphicsContext.current = previousContext }

            NSColor.textBackgroundColor.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: maximumSize)).fill()

            // Draw the attributed string, clipped to the thumbnail area.
            attributed.drawInRect(drawRect)

            MarkdownPerformanceInstrumentation.debug(
                "thumbnail.request scale=\(scale) width=\(Int(maximumSize.width)) height=\(Int(maximumSize.height)) characters=\(attributed.length)"
            )
            return true
        }), nil)
    }
}

private extension NSAttributedString {
    func drawInRect(_ rect: CGRect) {
        let textStorage = NSTextStorage(attributedString: self)
        let textContainer = NSTextContainer(containerSize: rect.size)
        let layoutManager = NSLayoutManager()

        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: rect.origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: rect.origin)
    }
}
