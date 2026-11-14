import Foundation
import MailCore

extension QuoteWording {
    /// The quote and forward header in the language the app is read in, so a Hebrew reader's replies quote in
    /// Hebrew, right to left, with Hebrew dates.
    static var localized: QuoteWording {
        QuoteWording(
            locale: .current,
            attribution: { date, sender in
                String(
                    localized: "On \(date), \(sender) wrote:", table: "Compose", bundle: .module,
                    comment: "Above a quoted message in a reply: when it was sent, and its sender's name and address")
            },
            forwardedMessage: String(
                localized: "Forward header: title", defaultValue: "---------- Forwarded message ---------",
                table: "Compose", bundle: .module, comment: "The first line of the header above a forwarded message"),
            from: String(
                localized: "Forward header: From", defaultValue: "From:", table: "Compose", bundle: .module,
                comment: "Forwarded message header field: the sender"),
            date: String(
                localized: "Forward header: Date", defaultValue: "Date:", table: "Compose", bundle: .module,
                comment: "Forwarded message header field: when it was sent"),
            subject: String(
                localized: "Forward header: Subject", defaultValue: "Subject:", table: "Compose", bundle: .module,
                comment: "Forwarded message header field: the subject"),
            to: String(
                localized: "Forward header: To", defaultValue: "To:", table: "Compose", bundle: .module,
                comment: "Forwarded message header field: the recipients"),
            cc: String(
                localized: "Forward header: Cc", defaultValue: "Cc:", table: "Compose", bundle: .module,
                comment: "Forwarded message header field: the copied recipients"))
    }
}
