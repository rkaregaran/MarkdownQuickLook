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

        handler(QLThumbnailReply(contextSize: maximumSize, drawing: { context -> Bool in
            let renderer = MarkdownDocumentRenderer()

            guard let document = try? renderer.prepareDocument(fileAt: request.fileURL) else {
                return false
            }

            let payload = DispatchQueue.main.sync {
                renderer.render(document: document)
            }

            let attributed = payload.attributedContent

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
            NSGraphicsContext.current = nsContext

            NSColor.textBackgroundColor.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: maximumSize)).fill()

            // Draw the attributed string, clipped to the thumbnail area.
            attributed.drawInRect(drawRect)

            NSGraphicsContext.current = nil
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
