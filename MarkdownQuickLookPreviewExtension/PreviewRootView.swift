import AppKit
import SwiftUI

struct PreviewRootView: View {
    let title: String
    let message: String?
    let attributedContent: NSAttributedString?
    @ObservedObject var tocViewModel: TableOfContentsViewModel

    var body: some View {
        HStack(spacing: 0) {
            if tocViewModel.shouldShowSidebar {
                TableOfContentsSidebar(viewModel: tocViewModel)
                    .frame(width: 220)
                    .transition(.move(edge: .leading))
                Divider()
            } else if tocViewModel.shouldShowExpandStrip {
                SidebarExpandStrip {
                    tocViewModel.collapsed = false
                }
                .frame(width: 28)
                .transition(.move(edge: .leading))
                Divider()
            }

            contentColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: tocViewModel.shouldShowSidebar)
        .animation(.easeInOut(duration: 0.18), value: tocViewModel.shouldShowExpandStrip)
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            if let attributedContent {
                MarkdownTextView(attributedText: attributedContent, tocViewModel: tocViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(message ?? "No preview available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
    }
}
