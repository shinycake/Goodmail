public import AppIntents
public import Foundation
import MailCore

/// Leaves the mailing list a message came from, the way the list offers: a one-click request or a message, sent
/// without opening anything. A list that only offers a page returns its link, for the shortcut to open.
public struct UnsubscribeIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource("Unsubscribe", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Leaves the mailing list a message came from. Returns the list's page when it has to be finished there.",
            table: "ShortcutActions"))

    @Parameter(title: LocalizedStringResource("Message", table: "ShortcutActions"))
    public var message: MessageEntity

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Unsubscribe from the list of \(\.$message)", table: "ShortcutActions")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<URL?> {
        let facts = try await Catalog(host: host).facts(ofMessage: message.id)
        guard let unsubscribe = facts.content?.unsubscribe else { throw IntentError.notAList }
        switch try await host.unsubscribe(unsubscribe, account: facts.envelope.account.id) {
        case .done: return .result(value: nil)
        case .openPage(let url): return .result(value: url)
        }
    }
}

/// Fetches new mail for every account now, as pulling down the Inbox does, and returns the conversations it
/// brought: what an automation that runs every so often acts on.
public struct CheckForNewMailIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Check for New Mail", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Fetches new mail for every account now, and returns the conversations that got new messages.",
            table: "ShortcutFlow"))

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[ThreadEntity]> {
        let catalog = Catalog(host: host)
        let newest = try await catalog.newestDate()
        try await host.refresh()
        return .result(value: try await catalog.threads(newerThan: newest))
    }
}

extension Catalog {
    /// The cached message the identifier names.
    func facts(ofMessage identifier: String) async throws -> MailFacts {
        guard let id = EntityID.message(identifier),
            let facts = try await host.messageFacts(inThreads: [id.thread]).first(where: {
                $0.content?.id == id.message
            })
        else { throw IntentError.gone }
        return facts
    }
}

extension Catalog {
    /// How many new conversations Check for New Mail returns at most.
    static let newMailLimit = 100

    /// When the newest stored conversation last got a message, or `nil` when nothing is stored yet.
    func newestDate() async throws -> Date? {
        try await host.threads(in: .allMail, limit: 1).first?.date
    }

    /// The conversations whose newest message came after `date`, newest first. Nothing before the first sync, when
    /// every conversation would be new. Spam and Trash aren't new mail.
    func threads(newerThan date: Date?) async throws -> [ThreadEntity] {
        guard let date else { return [] }
        let new = MailCondition.all([.date(.date, .after(date)), .flag(.inSpam, false), .flag(.inTrash, false)])
        return try await threads(matching: new, sortedBy: [], limit: Self.newMailLimit)
    }
}
