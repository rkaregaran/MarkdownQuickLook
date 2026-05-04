import Combine
import Foundation
import MarkdownRendering

@MainActor
final class TableOfContentsViewModel: ObservableObject {
    @Published private(set) var displayableAnchors: [HeadingAnchor] = []
    @Published var activeAnchorIndex: Int?
    @Published var collapsed: Bool = false

    var scrollHandler: ((Int) -> Void)?

    var hasEnoughHeadings: Bool { displayableAnchors.count >= 2 }
    var shouldShowSidebar: Bool { hasEnoughHeadings && !collapsed }
    var shouldShowExpandStrip: Bool { hasEnoughHeadings && collapsed }

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
}
