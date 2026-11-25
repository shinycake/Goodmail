import MailCore
import QuickLook
import UIKit

/// Opens a conversation's attachments in Quick Look, one at a time. Only the attachment tapped last opens: a tap on
/// another replaces a download still running, and another tap on the one downloading keeps its download, so a slow
/// file never opens over a quick one tapped after it and a double tap opens one preview.
final class AttachmentPreviewer {
    /// A download under way: what it fetches, the task fetching it, and the tap it answers, whose `loading` shows the
    /// wait and whose `finished` takes the file.
    private struct Download {
        let attachment: Attachment.ID
        let message: Message.ID
        let task: Task<Void, Never>
        var loading: (Bool) -> Void
        var finished: (Result<URL, any Error>) -> Void
    }

    private enum State {
        case idle
        case downloading(Download)
    }

    private var state = State.idle

    isolated deinit {
        if case .downloading(let download) = state { download.task.cancel() }
    }

    /// Fetches the attachment's file with `file`, `loading` showing the wait on whatever was tapped, then hands
    /// `finished` the file to preview or why there is none. A download a newer tap replaced stops its wait at once and
    /// finishes nothing; a tap on the attachment downloading, as from another place that shows it, moves the wait there.
    func open(
        _ attachment: Attachment, in message: Message.ID, file: @escaping () async throws -> URL,
        loading: @escaping (Bool) -> Void, finished: @escaping (Result<URL, any Error>) -> Void
    ) {
        if case .downloading(var download) = state {
            download.loading(false)
            loading(true)
            if download.attachment == attachment.id, download.message == message {
                download.loading = loading
                download.finished = finished
                state = .downloading(download)
                return
            }
            download.task.cancel()
        } else {
            loading(true)
        }
        let task = Task { [weak self] in
            let result: Result<URL, any Error>
            do {
                result = .success(try await file())
            } catch {
                result = .failure(error)
            }
            // Replacing a download cancels it, so a download not cancelled is still the newest.
            guard !Task.isCancelled, let self, case .downloading(let download) = state else { return }
            state = .idle
            download.loading(false)
            download.finished(result)
        }
        state = .downloading(
            Download(attachment: attachment.id, message: message, task: task, loading: loading, finished: finished))
    }

    /// Returns once the download running, if any, is done.
    func settled() async {
        if case .downloading(let download) = state { await download.task.value }
    }
}

/// Quick Look on one file, which it holds itself, so each preview shows the file it was opened for.
final class FilePreviewController: QLPreviewController, QLPreviewControllerDataSource {
    let file: URL

    init(file: URL) {
        self.file = file
        super.init(nibName: nil, bundle: nil)
        dataSource = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        file as NSURL
    }
}
