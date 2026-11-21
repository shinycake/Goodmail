import MailCore
import UIKit

/// The reader's Share menu: the conversation as a PDF, plain text, `.eml` files or an `.mbox` archive through the
/// share sheet, or printed. One export at a time: it owns the task that makes the files, and cancels it when the
/// reader leaves.
final class ConversationExporter {
    enum Destination {
        case print
        case share(ExportFormat)
    }

    /// What one export reads: the messages, the appearance each shows in as it is shared, what each may load, and
    /// where their inline images and raw sources come from.
    struct Conversation {
        let subject: String
        let messages: [Message]
        /// Light or dark, as the reader shows the message at the moment of sharing, sun button included. The PDF and
        /// print follow it; text, `.eml` and `.mbox` carry no colors of their own.
        let appearance: (Message.ID) -> UIUserInterfaceStyle
        let allowsRemoteContent: Set<Message.ID>
        let attachmentData: (Attachment, Message.ID) async throws -> Data
        let source: (Message.ID) async throws -> Data
    }

    /// One file an export makes, under the name the share sheet shows.
    private struct File {
        let name: String
        let data: Data
    }

    private weak var presenter: UIViewController?
    private var exporting: Task<Void, Never>?
    private let directory: URL

    init(
        presenter: UIViewController, directory: URL = FileManager.default.temporaryDirectory.appending(path: "Export")
    ) {
        self.presenter = presenter
        self.directory = directory
    }

    deinit {
        exporting?.cancel()
    }

    /// The toolbar's Share button: a menu of the formats, then Print, for the conversation `conversation` returns
    /// when one is chosen. When the toolbar is full it moves into the toolbar's More menu as a submenu. The share
    /// sheet and the print panel point from the item `anchor` returns, the button that shows the menu.
    func shareItem(
        anchor: @escaping () -> UIBarButtonItem?, conversation: @escaping () -> Conversation?
    ) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            title: String(
                localized: "Share", table: "Print", bundle: .module,
                comment: "Toolbar menu: share or print the conversation"),
            image: UIImage(systemName: "square.and.arrow.up"))
        func action(_ title: String, _ symbol: String, _ destination: Destination) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in
                guard let anchor = anchor(), let conversation = conversation() else { return }
                self?.export(conversation, to: destination, anchor: anchor)
            }
        }
        let formats = ExportFormat.allCases.map { action($0.title, $0.symbol, .share($0)) }
        let print = action(
            String(localized: "Print…", table: "Print", bundle: .module, comment: "Prints the conversation"),
            "printer", .print)
        item.menu = UIMenu(children: [UIMenu(options: .displayInline, children: formats), print])
        return item
    }

    func export(_ conversation: Conversation, to destination: Destination, anchor: UIBarButtonItem) {
        guard exporting == nil, !conversation.messages.isEmpty else { return }
        exporting = Task { [weak self] in
            defer { self?.exporting = nil }
            do {
                switch destination {
                case .print:
                    self?.printPDF(try await Self.pdf(of: conversation), named: conversation.subject, anchor: anchor)
                case .share(let format):
                    let files = try await Self.files(of: conversation, as: format)
                    try self?.share(files, anchor: anchor)
                }
            } catch is CancellationError {
            } catch {
                self?.presentFailure(error)
            }
        }
    }

    /// The contents of each file `format` makes, under its name.
    private static func files(of conversation: Conversation, as format: ExportFormat) async throws -> [File] {
        let fallback = String(
            localized: "Conversation", table: "Print", bundle: .module, comment: "Exported file name, no subject")
        let name = ExportFilename.name(for: conversation.subject, fallback: fallback, extension: format.fileExtension)
        switch format {
        case .pdf:
            return [File(name: name, data: try await pdf(of: conversation))]
        case .text:
            return [File(name: name, data: Data(text(of: conversation).utf8))]
        case .message:
            let sources = try await sources(of: conversation)
            let names = ExportFilename.names(
                for: conversation.subject, count: sources.count, fallback: fallback, extension: format.fileExtension)
            return zip(names, sources).map(File.init)
        case .archive:
            let sources = try await sources(of: conversation)
            let entries = zip(conversation.messages, sources).map { message, source in
                MboxArchive.Entry(source: source, sender: message.from.address, date: message.date)
            }
            return [File(name: name, data: MboxArchive.data(for: entries))]
        }
    }

    private static func pdf(of conversation: Conversation) async throws -> Data {
        try await ConversationPDF.data(
            for: conversation.messages, subject: conversation.subject, appearance: conversation.appearance,
            allowsRemoteContent: conversation.allowsRemoteContent, attachmentData: conversation.attachmentData)
    }

    /// Each message's raw source, oldest first, fetched one after another so a long thread doesn't flood the
    /// provider with requests.
    private static func sources(of conversation: Conversation) async throws -> [Data] {
        var sources: [Data] = []
        for message in conversation.messages {
            try Task.checkCancellation()
            sources.append(try await conversation.source(message.id))
        }
        return sources
    }

    private static func text(of conversation: Conversation) -> String {
        let labels = ConversationText.Labels(
            from: String(localized: "From:", table: "Print", bundle: .module, comment: "Printed header label"),
            to: String(localized: "To:", table: "Print", bundle: .module, comment: "Printed header label"),
            cc: String(localized: "Cc:", table: "Print", bundle: .module, comment: "Printed header label"),
            date: String(localized: "Date:", table: "Print", bundle: .module, comment: "Printed header label"))
        return ConversationText.text(for: conversation.messages, subject: conversation.subject, labels: labels) {
            $0.date.formatted(date: .long, time: .shortened)
        }
    }

    private func printPDF(_ pdf: Data, named subject: String, anchor: UIBarButtonItem) {
        guard presenter != nil else { return }
        let info = UIPrintInfo.printInfo()
        info.jobName = subject
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdf
        controller.present(from: anchor, animated: true)
    }

    /// Writes the files where the share sheet can offer them to save or send, then shows it.
    private func share(_ files: [File], anchor: UIBarButtonItem) throws {
        guard let presenter else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try files.map { file in
            let url = directory.appending(path: file.name)
            try file.data.write(to: url, options: .atomic)
            return url
        }
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceItem = anchor
        presenter.present(sheet, animated: true)
    }

    private func presentFailure(_ error: any Error) {
        let alert = UIAlertController(
            title: String(
                localized: "Couldn’t Export the Conversation", table: "Print", bundle: .module,
                comment: "Alert title when making the conversation's PDF, text or mail files for sharing or print fails"
            ),
            message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(localized: "OK", table: "Print", bundle: .module, comment: "Dismiss"), style: .default))
        presenter?.present(alert, animated: true)
    }
}
