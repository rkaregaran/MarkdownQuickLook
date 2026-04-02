import Cocoa
import MarkdownRendering
import Quartz
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let renderer = MarkdownDocumentRenderer()
    private let hostingView = NSHostingView(
        rootView: PreviewRootView(title: "Markdown Preview", message: "Loading preview...", attributedContent: nil)
    )

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func preparePreviewOfFile(at url: URL) async throws {
        do {
            let payload = try renderer.render(fileAt: url)
            hostingView.rootView = PreviewRootView(
                title: payload.title,
                message: nil,
                attributedContent: payload.attributedContent
            )
        } catch let error as MarkdownDocumentRendererError {
            hostingView.rootView = PreviewRootView(
                title: url.lastPathComponent,
                message: error.errorDescription,
                attributedContent: nil
            )
        } catch {
            hostingView.rootView = PreviewRootView(
                title: url.lastPathComponent,
                message: error.localizedDescription,
                attributedContent: nil
            )
        }
    }
}
