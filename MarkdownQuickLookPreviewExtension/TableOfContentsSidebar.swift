import MarkdownRendering
import SwiftUI

struct TableOfContentsSidebar: View {
    @ObservedObject var viewModel: TableOfContentsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.6))
    }

    private var header: some View {
        HStack {
            Text("Contents")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.displayableAnchors.enumerated()), id: \.offset) { index, anchor in
                    TableOfContentsRow(
                        anchor: anchor,
                        isActive: viewModel.activeAnchorIndex == index
                    ) {
                        viewModel.requestScroll(to: index)
                    }
                }
            }
            .padding(.vertical, 4)
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
            HStack(spacing: 6) {
                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 3)
                Text(displayText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .padding(.leading, indent)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
            .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .help(tooltipText)
        .onHover { isHovering = $0 }
    }

    private var indent: CGFloat {
        CGFloat(max(anchor.level - 1, 0)) * 12
    }

    private static func computeDisplayText(for raw: String) -> (display: AttributedString, tooltip: String) {
        guard var parsed = try? AttributedString(markdown: raw) else {
            return (AttributedString(raw), raw)
        }
        // Strip link attributes so the enclosing Button action isn't intercepted
        // by SwiftUI's link-handling on the link-attributed text run.
        parsed.link = nil
        return (parsed, String(parsed.characters))
    }
}
