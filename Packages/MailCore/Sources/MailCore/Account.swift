import Foundation

public struct AccountID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func generate() -> AccountID {
        AccountID(rawValue: UUID().uuidString)
    }
}

/// The mail service an account signs in to, which decides the provider that talks to it.
public enum MailService: String, CaseIterable, Codable, Hashable, Sendable {
    case gmail
    /// iCloud Mail, over IMAP and SMTP with an app-specific password.
    case icloud
    case outlook
    /// Any other mail account, on the IMAP and SMTP servers of its `MailServerSettings`.
    case imap

    /// Whether the service sorts its Inbox into categories (Primary, Promotions and the rest).
    public var hasInboxCategories: Bool {
        switch self {
        case .gmail: true
        case .icloud, .outlook, .imap: false
        }
    }

    /// Whether Mute is kept on the device rather than at the service. Gmail mutes with its `MUTED` label; Graph and
    /// IMAP have no such thing, so the store remembers their muted threads and keeps new replies out of the Inbox.
    public var mutesOnDevice: Bool {
        switch self {
        case .gmail: false
        case .icloud, .outlook, .imap: true
        }
    }

    /// Whether the service keeps the account's signature, so an edit reaches its other apps. Gmail keeps one on each
    /// send-as address; Graph and IMAP expose none, so Outlook's and iCloud's stay on the device.
    public var syncsSignature: Bool {
        switch self {
        case .gmail: true
        case .icloud, .outlook, .imap: false
        }
    }

    /// What deleting one of the user's labels does to its mail.
    public var labelDeletion: LabelDeletion {
        switch self {
        case .gmail: .keepsMail
        case .outlook: .movesMailToTrash
        case .icloud, .imap: .deletesMail
        }
    }
}

/// What deleting a user label does to the mail in it.
public enum LabelDeletion: Sendable {
    /// Gmail: the conversations lose the label and stay wherever else they are.
    case keepsMail
    /// Outlook: the folder, its subfolders and their mail move to Deleted Items.
    case movesMailToTrash
    /// IMAP: the server removes the folder and its messages for good.
    case deletesMail
}

public struct Account: Identifiable, Hashable, Sendable {
    public let id: AccountID
    public var email: String
    public var color: AccountColor
    public let service: MailService
    /// The name mail from this account is sent under, such as "Dana Levi". `nil` sends the address alone.
    public var name: String?

    public init(id: AccountID, email: String, color: AccountColor, service: MailService, name: String? = nil) {
        self.id = id
        self.email = email
        self.color = color
        self.service = service
        self.name = name
    }
}
