import AppIntents
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

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .gone: "That mail is no longer on this device."
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
