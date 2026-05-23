import Combine
import Foundation
import MarkdownRendering

@MainActor
final class TableOfContentsViewModel: ObservableObject {
    /// App Group `UserDefaults` key. Sidebar is hidden unless this is set to true.
    /// Toggle from the CLI:
    ///   defaults write group.com.rzkr.MarkdownQuickLook tableOfContentsSidebarEnabled -bool true
    /// Quick Look caches the extension process, so changes take effect only after
    /// `qlmanage -r && qlmanage -r cache` (or restarting Finder).
    static let featureFlagKey = "tableOfContentsSidebarEnabled"

    /// Minimum displayable (h1–h3) heading count before the sidebar auto-shows.
    static let headingThreshold = 10

    @Published private(set) var displayableAnchors: [HeadingAnchor] = []
    @Published var activeAnchorIndex: Int?

    var scrollHandler: ((Int) -> Void)?

    private let featureEnabled: Bool

    convenience init() {
        let defaults = UserDefaults(suiteName: MarkdownSettingsStore.suiteName) ?? .standard
        self.init(featureEnabled: defaults.bool(forKey: Self.featureFlagKey))
    }

    init(featureEnabled: Bool) {
        self.featureEnabled = featureEnabled
    }

    var shouldShowSidebar: Bool {
        featureEnabled && displayableAnchors.count >= Self.headingThreshold
    }

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
