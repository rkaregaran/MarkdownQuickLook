import MarkdownRendering
import SwiftUI

struct TableOfContentsSidebar: View {
    @ObservedObject var viewModel: TableOfContentsViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(viewModel.displayableAnchors.enumerated()), id: \.offset) { index, anchor in
                    TableOfContentsRow(
                        anchor: anchor,
                        isActive: viewModel.activeAnchorIndex == index
                    ) {
                        viewModel.requestScroll(to: index)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct TableOfContentsRow: View {
    let anchor: HeadingAnchor
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    private let displayText: AttributedString
    private let tooltipText: String

    init(anchor: HeadingAnchor, isActive: Bool, action: @escaping () -> Void) {
        self.anchor = anchor
        self.isActive = isActive
        self.action = action
        let computed = Self.computeDisplayText(for: anchor.text)
        self.displayText = computed.display
        self.tooltipText = computed.tooltip
    }

    var body: some View {
        Button(action: action) {
            Text(displayText)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(textColor)
                .padding(.leading, indent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(backgroundFill)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .help(tooltipText)
        .onHover { isHovering = $0 }
    }

    private var indent: CGFloat {
        CGFloat(max(anchor.level - 1, 0)) * 12
    }

    private var textColor: Color {
        if isActive { return .white }
        return .secondary
    }

    private var backgroundFill: Color {
        if isActive { return Color.accentColor }
        if isHovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private static func computeDisplayText(for raw: String) -> (display: AttributedString, tooltip: String) {
        guard var parsed = try? AttributedString(markdown: raw) else {
            return (AttributedString(raw), raw)
        }
        parsed.link = nil
        return (parsed, String(parsed.characters))
    }
}
