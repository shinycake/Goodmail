import AppIntents
public import CoreTransferable
import Foundation
import MailCore

/// Mail as plain text, for the actions that take text: Use Model, Ask ChatGPT, Summarize, Show Result and Copy to
/// Clipboard. A message reads as an email printout does, its headers then its body, so a model knows who wrote what
/// and when.
extension MessageEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.plainText)
    }

    /// The headers a reader looks at, then the body, or the preview when the body isn't on the device.
    var plainText: String {
        let from = sender.recipient
        let sent = dateSent.formatted(date: .complete, time: .shortened)
        var lines = [String(localized: LocalizedStringResource("From: \(from)", table: "ShortcutText"))]
        if !to.isEmpty {
            let people = to.recipients.formatted()
            lines.append(String(localized: LocalizedStringResource("To: \(people)", table: "ShortcutText")))
        }
        if !cc.isEmpty {
            let people = cc.recipients.formatted()
            lines.append(String(localized: LocalizedStringResource("Cc: \(people)", table: "ShortcutText")))
        }
        lines.append(String(localized: LocalizedStringResource("Date: \(sent)", table: "ShortcutText")))
        if let subject, !subject.isEmpty {
            lines.append(String(localized: LocalizedStringResource("Subject: \(subject)", table: "ShortcutText")))
        }
        if !attachmentNames.isEmpty {
            let files = attachmentNames.formatted()
            lines.append(String(localized: LocalizedStringResource("Attachments: \(files)", table: "ShortcutText")))
        }
        return lines.joined(separator: "\n") + "\n\n" + (body ?? snippet)
    }
}

/// A conversation reads as its cached messages, oldest first, or as its latest message's headers and preview when
/// none are cached yet.
extension ThreadEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.plainText)
    }

    /// Between two messages of a conversation.
    private static let divider = "\n\n――――――――――\n\n"

    var plainText: String {
        guard messages.isEmpty else { return messages.map(\.plainText).joined(separator: Self.divider) }
        let from = senderName.isEmpty ? senderAddress : Contact(name: senderName, address: senderAddress).typedForm
        let sent = date.formatted(date: .complete, time: .shortened)
        let subject = title
        let lines = [
            String(localized: LocalizedStringResource("From: \(from)", table: "ShortcutText")),
            String(localized: LocalizedStringResource("Date: \(sent)", table: "ShortcutText")),
            String(localized: LocalizedStringResource("Subject: \(subject)", table: "ShortcutText")),
        ]
        return lines.joined(separator: "\n") + "\n\n" + (description ?? "")
    }
}
