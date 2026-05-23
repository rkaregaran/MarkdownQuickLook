import AppKit
import MarkdownRendering
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    @ObservedObject var tocViewModel: TableOfContentsViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: tocViewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Use TextKit 1 explicitly — recomputeAnchorPositions relies on NSLayoutManager,
        // which is nil under TextKit 2 unless we opt into the legacy stack.
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributedText)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        context.coordinator.lastAttributedText = attributedText
        context.coordinator.attach(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.viewModel = tocViewModel

        // Only rebuild text storage and anchor positions when the attributed
        // content actually changes. SwiftUI calls updateNSView on every observed
        // state change (scroll-spy active index, hover state, etc.); blindly
        // replacing the text storage would invalidate layout and reset the
        // scroll position mid-interaction.
        if context.coordinator.lastAttributedText !== attributedText {
            textView.textStorage?.setAttributedString(attributedText)
            context.coordinator.lastAttributedText = attributedText
            context.coordinator.resetSuppressionWindow()
            context.coordinator.scheduleAnchorRecompute()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var viewModel: TableOfContentsViewModel {
            didSet { wireScrollHandler() }
        }
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        var lastAttributedText: NSAttributedString?
        private(set) var anchorYPositions: [CGFloat] = []
        private var suppressScrollSpyUntil: Date?

        init(viewModel: TableOfContentsViewModel) {
            self.viewModel = viewModel
            super.init()
            wireScrollHandler()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView

            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            // Initial layout pass so anchor positions are available immediately.
            scheduleAnchorRecompute()
        }

        func resetSuppressionWindow() {
            suppressScrollSpyUntil = nil
        }

        /// Defer the recompute by one runloop tick so SwiftUI has a chance to lay out
        /// the hosting view and set the text container's width. Computing positions
        /// while the container width is still 0 produces wildly wrong values.
        func scheduleAnchorRecompute() {
            DispatchQueue.main.async { [weak self] in
                self?.recomputeAnchorPositions()
                self?.updateActiveAnchor()
            }
        }

        func recomputeAnchorPositions() {
            guard let textView, let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                anchorYPositions = []
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let inset = textView.textContainerInset.height

            anchorYPositions = viewModel.displayableAnchors.map { anchor in
                // anchor.range has length 0 (positional); expand to 1 so glyphRange has a
                // non-empty range to resolve. The parser guarantees heading text is non-empty,
                // so location + 1 is always within bounds.
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: anchor.range.location, length: 1),
                    actualCharacterRange: nil
                )
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                return rect.minY + inset
            }
        }

        @objc func boundsDidChange(_ notification: Notification) {
            updateActiveAnchor()
        }

        private func updateActiveAnchor() {
            if let suppress = suppressScrollSpyUntil, Date() < suppress {
                return
            }
            suppressScrollSpyUntil = nil

            guard let scrollView else { return }
            let visibleTop = scrollView.contentView.bounds.minY
            let newIndex = TableOfContentsViewModel.computeActiveAnchorIndex(
                visibleTop: visibleTop,
                anchorYPositions: anchorYPositions
            )
            if newIndex != viewModel.activeAnchorIndex {
                viewModel.activeAnchorIndex = newIndex
            }
        }

        private func wireScrollHandler() {
            viewModel.scrollHandler = { [weak self] index in
                self?.scrollToAnchor(at: index)
            }
        }

        private func scrollToAnchor(at index: Int) {
            guard let textView, let scrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  viewModel.displayableAnchors.indices.contains(index) else { return }

            let anchor = viewModel.displayableAnchors[index]
            // Force layout so glyph positions are current. At click time the text view
            // is on screen, so layout is well-defined here (unlike the initial setup
            // path where the view may not yet have its real frame).
            layoutManager.ensureLayout(for: textContainer)

            // Use lineFragmentRect — gives the line's rect in text container coords.
            // Convert to text view bounds by adding the top container inset.
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: anchor.range.location)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let viewY = lineRect.origin.y + textView.textContainerInset.height

            // Aim 8pt below the visible top so the heading isn't flush against the edge.
            let targetY = max(0, viewY - 8)

            suppressScrollSpyUntil = Date().addingTimeInterval(0.2)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
