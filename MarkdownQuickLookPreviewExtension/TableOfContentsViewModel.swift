import Combine
import Foundation
import MarkdownRendering

@MainActor
final class TableOfContentsViewModel: ObservableObject {
    @Published private(set) var displayableAnchors: [HeadingAnchor] = []
    @Published var activeAnchorIndex: Int?

    var scrollHandler: ((Int) -> Void)?

    var shouldShowSidebar: Bool { displayableAnchors.count >= 2 }

    func setAnchors(_ anchors: [HeadingAnchor]) {
        displayableAnchors = anchors.filter { $0.level <= 3 }
        if let active = activeAnchorIndex, active >= displayableAnchors.count {
            activeAnchorIndex = nil
        }
    }

    func requestScroll(to displayIndex: Int) {
        guard displayableAnchors.indices.contains(displayIndex) else { return }
        activeAnchorIndex = displayIndex
        scrollHandler?(displayIndex)
    }

    static let activationOffset: CGFloat = 24

    static func computeActiveAnchorIndex(
        visibleTop: CGFloat,
        anchorYPositions: [CGFloat],
        activationOffset: CGFloat = TableOfContentsViewModel.activationOffset
    ) -> Int? {
        guard anchorYPositions.isEmpty == false else { return nil }
        let cutoff = visibleTop + activationOffset
        if let lastBelow = anchorYPositions.lastIndex(where: { $0 <= cutoff }) {
            return lastBelow
        }
        return 0
    }
}
