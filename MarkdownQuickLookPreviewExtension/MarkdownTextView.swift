import AppKit
import Combine
import MarkdownRendering
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    @ObservedObject var tocViewModel: TableOfContentsViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: tocViewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
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

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.textStorage?.setAttributedString(attributedText)
        context.coordinator.viewModel = tocViewModel
        context.coordinator.recomputeAnchorPositions()
    }

    @MainActor
    final class Coordinator: NSObject {
        var viewModel: TableOfContentsViewModel {
            didSet { wireScrollHandler() }
        }
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
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
            guard let scrollView,
                  anchorYPositions.indices.contains(index) else { return }

            let targetY = max(0, anchorYPositions[index] - 8)
            suppressScrollSpyUntil = Date().addingTimeInterval(0.2)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
