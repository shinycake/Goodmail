public import AppIntents
import MailCore

/// Opens a thread in the reader.
public struct OpenThreadIntent: OpenIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Open Conversation", table: "ShortcutMail")
    public static let description = IntentDescription(
        LocalizedStringResource("Opens a conversation in Goodmail.", table: "ShortcutMail"))

    @Parameter(title: LocalizedStringResource("Conversation", table: "ShortcutMail"))
    public var target: ThreadEntity

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(target: ThreadEntity) {
        self.target = target
    }

    public func perform() async throws -> some IntentResult {
        // The lookup reads the database, so it runs here, off the main actor; only showing the route hops there.
        guard let route = try Catalog(host: host).route(toThread: target.id) else { throw IntentError.gone }
        await host.open(route)
        return .result()
    }
}

/// Opens one account's mailbox.
public struct OpenMailboxIntent: OpenIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource("Open Mailbox", table: "ShortcutMail")
    public static let description = IntentDescription(
        LocalizedStringResource("Opens a mailbox in Goodmail.", table: "ShortcutMail"))

    @Parameter(title: LocalizedStringResource("Mailbox", table: "ShortcutMail"))
    public var target: MailboxEntity

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public init(target: MailboxEntity) {
        self.target = target
    }

    public func perform() async throws -> some IntentResult {
        guard let mailbox = target.mailbox else { throw IntentError.gone }
        await host.open(.mailbox(mailbox))
        return .result()
    }
}

/// Why an intent couldn't run.
enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    /// What it was asked about is no longer on the device, as when its account was removed.
    case gone
    /// A move or label change named a mailbox that isn't a place mail can go, as Sent or Starred.
    case notAPlace
    /// Unsubscribe was asked of a message that isn't from a mailing list.
    case notAList
    /// A recipient that doesn't read as an email address, as it was given.
    case notAnAddress(String)
    /// A message with no one to send it to.
    case noRecipients
    /// Get Open Conversation ran with no conversation open.
    case nothingOpen

    init(_ error: WrittenMailError) {
        switch error {
        case .notAnAddress(let text): self = .notAnAddress(text)
        case .noRecipients: self = .noRecipients
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAnAddress(let text):
            LocalizedStringResource("“\(text)” isn't an email address.", table: "ShortcutMail")
        case .noRecipients: LocalizedStringResource("Choose someone to send it to.", table: "ShortcutMail")
        case .gone: LocalizedStringResource("That mail is no longer on this device.", table: "ShortcutMail")
        case .notAPlace:
            LocalizedStringResource(
                "Mail can't be moved there. Choose the Inbox, Spam, Trash or a label.", table: "ShortcutMail")
        case .notAList: LocalizedStringResource("That message isn't from a mailing list.", table: "ShortcutMail")
        case .nothingOpen:
            LocalizedStringResource("No conversation is open in Goodmail.", table: "ShortcutFlow")
        }
    }
}

extension Catalog {
    /// Where opening the thread goes: the reader, from the mailbox the thread is in. `nil` once it is gone.
    func route(toThread identifier: String) throws -> Route? {
        guard let id = EntityID.thread(identifier), let thread = try host.threads([id]).first else { return nil }
        return .thread(id, in: Mailbox.holding(thread.labelIDs))
    }
}

/// Opens the Inbox of every account.
public struct OpenInboxIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource("Open Inbox", table: "ShortcutMail")
    public static let description = IntentDescription(
        LocalizedStringResource("Opens the Inbox in Goodmail.", table: "ShortcutMail"))
    public static let supportedModes: IntentModes = .foreground

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func perform() async throws -> some IntentResult {
        await host.open(.mailbox(.inbox))
        return .result()
    }
}

/// Starts a new message, from the account given or else the first, filled in with what the shortcut wrote.
public struct NewMessageIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource("New Message", table: "ShortcutMail")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Starts a new message in Goodmail, with the recipients, subject, text and files you give it.",
            table: "ShortcutMail"))
    public static let supportedModes: IntentModes = .foreground

    @Parameter(title: LocalizedStringResource("From", table: "ShortcutMail"))
    public var account: AccountEntity?
    @Parameter(title: LocalizedStringResource("To", table: "ShortcutMail"))
    public var to: [IntentPerson]?
    @Parameter(title: LocalizedStringResource("CC", table: "ShortcutMail"))
    public var cc: [IntentPerson]?
    @Parameter(title: LocalizedStringResource("BCC", table: "ShortcutMail"))
    public var bcc: [IntentPerson]?
    @Parameter(title: LocalizedStringResource("Subject", table: "ShortcutMail"))
    public var subject: String?
    @Parameter(
        title: LocalizedStringResource("Body", table: "ShortcutMail"),
        inputOptions: String.IntentInputOptions(multiline: true))
    public var body: String?
    @Parameter(title: LocalizedStringResource("Attachments", table: "ShortcutMail"))
    public var attachments: [IntentFile]?

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func perform() async throws -> some IntentResult {
        let draft = try Catalog(host: host).newDraft(
            WrittenMail(
                to: (to ?? []).recipients, cc: (cc ?? []).recipients, bcc: (bcc ?? []).recipients, subject: subject,
                text: body ?? "",
                attachments: attachments.drafted), from: account?.id)
        await host.open(.compose(draft))
        return .result()
    }
}
