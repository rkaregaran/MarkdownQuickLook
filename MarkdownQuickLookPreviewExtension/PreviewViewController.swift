import Cocoa
import MarkdownRendering
import Quartz
import SwiftUI

@MainActor
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let renderer = MarkdownDocumentRenderer()
    private let hostingView = NSHostingView(
        rootView: PreviewRootView(title: "Markdown Preview", message: "Loading preview...", attributedContent: nil)
    )
    private let loadingCoordinator = PreviewLoadingCoordinator<PreviewLoadResult>()

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
        let request = loadingCoordinator.beginRequest {
            Self.prepareDocumentResult(for: url)
        }
        hostingView.rootView = loadingRootView(for: url)

        let result = await withTaskCancellationHandler {
            await request.task.value
        } onCancel: {
            request.task.cancel()
        }

        guard Task.isCancelled == false else {
            _ = loadingCoordinator.cancelRequest(request.requestID, task: request.task)
            return
        }

        guard loadingCoordinator.finishRequest(request.requestID) else {
            return
        }

        switch result {
        case .prepared(let document):
            let payload = renderer.render(document: document)
            hostingView.rootView = PreviewRootView(
                title: payload.title,
                message: nil,
                attributedContent: payload.attributedContent
            )
        case .rendererError(let error):
            hostingView.rootView = PreviewRootView(
                title: url.lastPathComponent,
                message: error.errorDescription,
                attributedContent: nil
            )
        case .failure(let message):
            hostingView.rootView = PreviewRootView(
                title: url.lastPathComponent,
                message: message,
                attributedContent: nil
            )
        case .cancelled:
            break
        }
    }

    private func loadingRootView(for url: URL) -> PreviewRootView {
        PreviewRootView(
            title: url.lastPathComponent,
            message: "Loading preview...",
            attributedContent: nil
        )
    }

    private nonisolated static func prepareDocumentResult(for url: URL) -> PreviewLoadResult {
        guard Task.isCancelled == false else {
            return .cancelled
        }

        do {
            let document = try MarkdownDocumentRenderer().prepareDocument(fileAt: url)
            return Task.isCancelled ? .cancelled : .prepared(document)
        } catch let error as MarkdownDocumentRendererError {
            return Task.isCancelled ? .cancelled : .rendererError(error)
        } catch {
            return Task.isCancelled ? .cancelled : .failure(error.localizedDescription)
        }
    }
}

private enum PreviewLoadResult: Sendable {
    case prepared(MarkdownPreparedDocument)
    case rendererError(MarkdownDocumentRendererError)
    case failure(String)
    case cancelled
}
