import Cocoa
import MarkdownRendering
import Quartz
import SwiftUI

@MainActor
final class PreviewViewController: NSViewController, QLPreviewingController {
    typealias PrepareDocumentResultProvider = @Sendable (URL) -> PreviewLoadResult
    typealias RenderProvider = @MainActor (
        MarkdownPreparedDocument,
        @escaping @MainActor @Sendable () -> Bool
    ) async throws -> MarkdownRenderPayload

    private let hostingView = NSHostingView(
        rootView: PreviewRootView(title: "Markdown Preview", message: "Loading preview...", attributedContent: nil)
    )
    private let loadingCoordinator: PreviewLoadingCoordinator<PreviewLoadResult>
    private let prepareDocumentResultProvider: PrepareDocumentResultProvider
    private let renderProvider: RenderProvider

    override init(nibName nibNameOrNil: NSNib.Name? = nil, bundle nibBundleOrNil: Bundle? = nil) {
        loadingCoordinator = PreviewLoadingCoordinator()
        prepareDocumentResultProvider = { url in
            PreviewViewController.prepareDocumentResult(for: url)
        }
        renderProvider = PreviewViewController.renderPayload(for:shouldContinue:)
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    init(
        loadingCoordinator: PreviewLoadingCoordinator<PreviewLoadResult>? = nil,
        prepareDocumentResultProvider: @escaping PrepareDocumentResultProvider,
        renderProvider: @escaping RenderProvider
    ) {
        self.loadingCoordinator = loadingCoordinator ?? PreviewLoadingCoordinator()
        self.prepareDocumentResultProvider = prepareDocumentResultProvider
        self.renderProvider = renderProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = PreviewSizing.loadingPreferredContentSize

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
        preferredContentSize = PreviewSizing.loadingPreferredContentSize
        let request = loadingCoordinator.beginRequest {
            self.prepareDocumentResultProvider(url)
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

        guard loadingCoordinator.isActive(request.requestID) else {
            return
        }

        do {
            switch result {
            case .prepared(let document):
                let payload = try await renderProvider(document) {
                    self.loadingCoordinator.isActive(request.requestID)
                }
                guard loadingCoordinator.finishRequest(request.requestID) else {
                    return
                }
                hostingView.rootView = PreviewRootView(
                    title: payload.title,
                    message: nil,
                    attributedContent: payload.attributedContent
                )
                preferredContentSize = PreviewSizing.preferredContentSize(
                    forRenderedText: payload.attributedContent.string
                )
            case .rendererError(let error):
                guard loadingCoordinator.finishRequest(request.requestID) else {
                    return
                }
                hostingView.rootView = PreviewRootView(
                    title: url.lastPathComponent,
                    message: error.errorDescription,
                    attributedContent: nil
                )
                preferredContentSize = PreviewSizing.errorPreferredContentSize
            case .failure(let message):
                guard loadingCoordinator.finishRequest(request.requestID) else {
                    return
                }
                hostingView.rootView = PreviewRootView(
                    title: url.lastPathComponent,
                    message: message,
                    attributedContent: nil
                )
                preferredContentSize = PreviewSizing.errorPreferredContentSize
            case .cancelled:
                _ = loadingCoordinator.cancelRequest(request.requestID, task: request.task)
            }
        } catch is CancellationError {
            _ = loadingCoordinator.cancelRequest(request.requestID, task: request.task)
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
        } catch is CancellationError {
            return .cancelled
        } catch let error as MarkdownDocumentRendererError {
            return Task.isCancelled ? .cancelled : .rendererError(error)
        } catch {
            return Task.isCancelled ? .cancelled : .failure(error.localizedDescription)
        }
    }

    private static func renderPayload(
        for document: MarkdownPreparedDocument,
        shouldContinue: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> MarkdownRenderPayload {
        try await MarkdownDocumentRenderer().render(document: document, shouldContinue: shouldContinue)
    }

    var testingCurrentRootView: PreviewRootView {
        hostingView.rootView
    }

    var testingHasActiveRequest: Bool {
        loadingCoordinator.hasActiveRequest
    }
}

enum PreviewLoadResult: Sendable {
    case prepared(MarkdownPreparedDocument)
    case rendererError(MarkdownDocumentRendererError)
    case failure(String)
    case cancelled
}
