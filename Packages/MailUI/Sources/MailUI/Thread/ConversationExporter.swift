import MailCore
import UIKit

/// Prints a conversation or shares it as a PDF from the reader. One export at a time: it owns the task that
/// lays the pages out, and cancels it when the reader leaves.
final class ConversationExporter {
    enum Destination {
        case print
        case share
    }

    /// What one export lays out: the messages, what each may load, and where their inline images come from.
    struct Conversation {
        let subject: String
        let messages: [Message]
        let allowsRemoteContent: Set<Message.ID>
        let attachmentData: (Attachment, Message.ID) async throws -> Data
    }

    private weak var presenter: UIViewController?
    private var exporting: Task<Void, Never>?
    private let directory: URL

    init(presenter: UIViewController, directory: URL = FileManager.default.temporaryDirectory.appending(path: "PDF")) {
        self.presenter = presenter
        self.directory = directory
    }

    deinit {
        exporting?.cancel()
    }

    /// The reader's Print and Share as PDF actions, for the conversation `conversation` returns when chosen,
    /// anchored to `anchor` where the share sheet needs one.
    func menuElements(
        anchor: UIBarButtonItem, conversation: @escaping () -> Conversation?
    ) -> [UIMenuElement] {
        [
            UIAction(
                title: String(localized: "Print…", table: "Print", bundle: .module, comment: "Prints the conversation"),
                image: UIImage(systemName: "printer")
            ) { [weak self] _ in
                guard let conversation = conversation() else { return }
                self?.export(conversation, to: .print, anchor: anchor)
            },
            UIAction(
                title: String(
                    localized: "Share as PDF…", table: "Print", bundle: .module,
                    comment: "Shares the conversation as a PDF file"),
                image: UIImage(systemName: "doc.richtext")
            ) { [weak self] _ in
                guard let conversation = conversation() else { return }
                self?.export(conversation, to: .share, anchor: anchor)
            },
        ]
    }

    func export(_ conversation: Conversation, to destination: Destination, anchor: UIBarButtonItem) {
        guard exporting == nil, !conversation.messages.isEmpty else { return }
        exporting = Task { [weak self] in
            defer { self?.exporting = nil }
            do {
                let data = try await ConversationPDF.data(
                    for: conversation.messages, subject: conversation.subject,
                    allowsRemoteContent: conversation.allowsRemoteContent,
                    attachmentData: conversation.attachmentData)
                try self?.present(data, named: conversation.subject, to: destination, anchor: anchor)
            } catch is CancellationError {
            } catch {
                self?.presentFailure(error)
            }
        }
    }

    private func present(_ data: Data, named subject: String, to destination: Destination, anchor: UIBarButtonItem)
        throws
    {
        guard let presenter else { return }
        switch destination {
        case .print:
            let info = UIPrintInfo.printInfo()
            info.jobName = subject
            info.outputType = .general
            let controller = UIPrintInteractionController.shared
            controller.printInfo = info
            controller.printingItem = data
            controller.present(from: anchor, animated: true)
        case .share:
            let url = try write(data, named: subject)
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceItem = anchor
            presenter.present(sheet, animated: true)
        }
    }

    /// The PDF as a file named after the subject, which the share sheet offers to save or send.
    private func write(_ data: Data, named subject: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: Self.filename(for: subject))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The subject without the characters a file name can't hold, or "Conversation" for none.
    static func filename(for subject: String) -> String {
        let cleaned = subject.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines))
            .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let name =
            cleaned.isEmpty
            ? String(localized: "Conversation", table: "Print", bundle: .module, comment: "PDF file name, no subject")
            : String(cleaned.prefix(100))
        return name + ".pdf"
    }

    private func presentFailure(_ error: any Error) {
        let alert = UIAlertController(
            title: String(
                localized: "Couldn’t Make a PDF", table: "Print", bundle: .module,
                comment: "Alert title when laying out the conversation for print or PDF fails"),
            message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(localized: "OK", table: "Print", bundle: .module, comment: "Dismiss"), style: .default))
        presenter?.present(alert, animated: true)
    }
}
