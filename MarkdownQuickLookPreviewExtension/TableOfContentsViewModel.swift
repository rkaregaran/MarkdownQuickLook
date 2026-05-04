import Combine
import Foundation
import MarkdownRendering

@MainActor
final class TableOfContentsViewModel: ObservableObject {
    static let collapsedDefaultsKey = "tableOfContentsCollapsed"

    @Published private(set) var displayableAnchors: [HeadingAnchor] = []
    @Published var activeAnchorIndex: Int?
    @Published var collapsed: Bool {
        didSet {
            guard collapsed != oldValue else { return }
            defaults.set(collapsed, forKey: Self.collapsedDefaultsKey)
        }
    }

    var scrollHandler: ((Int) -> Void)?

    private let defaults: UserDefaults

    convenience init() {
        let defaults = UserDefaults(suiteName: MarkdownSettingsStore.suiteName) ?? .standard
        self.init(defaults: defaults)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.synchronize()
        self.collapsed = defaults.bool(forKey: Self.collapsedDefaultsKey)
    }

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
