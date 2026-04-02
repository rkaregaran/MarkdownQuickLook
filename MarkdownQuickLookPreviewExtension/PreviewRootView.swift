import AppKit
import SwiftUI

struct PreviewRootView: View {
    let title: String
    let message: String?
    let attributedContent: NSAttributedString?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            if let attributedContent {
                MarkdownTextView(attributedText: attributedContent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(message ?? "No preview available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
