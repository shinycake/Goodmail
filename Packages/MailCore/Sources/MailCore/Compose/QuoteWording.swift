import Foundation

/// The words above a quoted or forwarded message, in the language the app is read in, with its dates and direction.
/// `english` is the default; the app passes its localized wording.
public struct QuoteWording: Sendable {
    /// Formats the dates, and sets the direction the header reads in.
    public var locale: Locale
    /// "On <date>, <sender> wrote:", given the formatted date and the sender's mailbox.
    public var attribution: @Sendable (_ date: String, _ sender: String) -> String
    /// The forward header's first line and its field names, each with its colon.
    public var forwardedMessage: String
    public var from: String
    public var date: String
    public var subject: String
    public var to: String
    public var cc: String

    public init(
        locale: Locale, attribution: @escaping @Sendable (_ date: String, _ sender: String) -> String,
        forwardedMessage: String, from: String, date: String, subject: String, to: String, cc: String
    ) {
        self.locale = locale
        self.attribution = attribution
        self.forwardedMessage = forwardedMessage
        self.from = from
        self.date = date
        self.subject = subject
        self.to = to
        self.cc = cc
    }

    public static let english = QuoteWording(
        locale: Locale(identifier: "en_US"), attribution: { "On \($0), \($1) wrote:" },
        forwardedMessage: "---------- Forwarded message ---------", from: "From:", date: "Date:", subject: "Subject:",
        to: "To:", cc: "Cc:")

    var isRightToLeft: Bool { locale.language.characterDirection == .rightToLeft }

    /// The `dir` of the header's HTML.
    var direction: String { isRightToLeft ? "rtl" : "ltr" }

    /// `text` set apart from the words around it, so an address or a date keeps its own order inside a right-to-left
    /// sentence. Left-to-right text needs nothing.
    func isolated(_ text: String) -> String {
        isRightToLeft ? "\u{2068}\(text)\u{2069}" : text
    }
}
