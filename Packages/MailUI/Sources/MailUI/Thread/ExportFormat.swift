import Foundation
import MailCore

/// What the reader's Share menu offers a conversation as.
enum ExportFormat: CaseIterable {
    /// The conversation laid out as the reader shows it, on paper-sized pages.
    case pdf
    /// Its headers and words, for anything that takes text.
    case text
    /// Each message's raw source as an `.eml` file, which mail apps open as the message itself.
    case message
    /// The whole conversation in one `.mbox` file, which mail apps import as a mailbox.
    case archive

    var title: String {
        switch self {
        case .pdf:
            String(localized: "PDF", table: "Print", bundle: .module, comment: "Share menu: the conversation as a PDF")
        case .text:
            String(
                localized: "Plain Text", table: "Print", bundle: .module,
                comment: "Share menu: the conversation as a text file")
        case .message:
            String(
                localized: "Email File (.eml)", table: "Print", bundle: .module,
                comment: "Share menu: each message's original source as an .eml file")
        case .archive:
            String(
                localized: "Mailbox Archive (.mbox)", table: "Print", bundle: .module,
                comment: "Share menu: the whole conversation as one .mbox mailbox file")
        }
    }

    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .text: "doc.plaintext"
        case .message: "envelope"
        case .archive: "archivebox"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .text: "txt"
        case .message: "eml"
        case .archive: "mbox"
        }
    }
}
