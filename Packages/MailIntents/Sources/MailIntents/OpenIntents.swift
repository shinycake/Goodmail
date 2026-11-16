public import AppIntents
import MailCore

/// Opens a thread in the reader.
public struct OpenThreadIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Conversation"
    public static let description = IntentDescription("Opens a conversation in Goodmail.")

    @Parameter(title: "Conversation")
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
    public static let title: LocalizedStringResource = "Open Mailbox"
    public static let description = IntentDescription("Opens a mailbox in Goodmail.")

    @Parameter(title: "Mailbox")
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

    init(_ error: WrittenMailError) {
        switch error {
        case .notAnAddress(let text): self = .notAnAddress(text)
        case .noRecipients: self = .noRecipients
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAnAddress(let text): "“\(text)” isn't an email address."
        case .noRecipients: "Choose someone to send it to."
        case .gone: "That mail is no longer on this device."
        case .notAPlace: "Mail can't be moved there. Choose the Inbox, Spam, Trash or a label."
        case .notAList: "That message isn't from a mailing list."
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
    public static let title: LocalizedStringResource = "Open Inbox"
    public static let description = IntentDescription("Opens the Inbox in Goodmail.")
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
    public static let title: LocalizedStringResource = "New Message"
    public static let description = IntentDescription(
        "Starts a new message in Goodmail, with the recipients, subject, text and files you give it.")
    public static let supportedModes: IntentModes = .foreground

    @Parameter(title: "From")
    public var account: AccountEntity?
    @Parameter(title: "To")
    public var to: [IntentPerson]?
    @Parameter(title: "CC")
    public var cc: [IntentPerson]?
    @Parameter(title: "BCC")
    public var bcc: [IntentPerson]?
    @Parameter(title: "Subject")
    public var subject: String?
    @Parameter(title: "Body", inputOptions: String.IntentInputOptions(multiline: true))
    public var body: String?
    @Parameter(title: "Attachments")
    public var attachments: [IntentFile]?

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func perform() async throws -> some IntentResult {
        let draft = try Catalog(host: host).newDraft(
            WrittenMail(
                to: to.recipients, cc: cc.recipients, bcc: bcc.recipients, subject: subject, text: body ?? "",
                attachments: attachments.drafted), from: account?.id)
        await host.open(.compose(draft))
        return .result()
    }
}
