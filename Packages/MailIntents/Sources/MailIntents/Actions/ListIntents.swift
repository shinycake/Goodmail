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
        let facts = try Catalog(host: host).facts(ofMessage: message.id)
        guard let unsubscribe = facts.content?.unsubscribe else { throw IntentError.notAList }
        switch try await host.unsubscribe(unsubscribe, account: facts.envelope.account.id) {
        case .done: return .result(value: nil)
        case .openPage(let url): return .result(value: url)
        }
    }
}

/// Fetches new mail for every account now, as pulling down the Inbox does.
public struct CheckForNewMailIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Check for New Mail", table: "ShortcutActions")
    public static let description = IntentDescription(
        LocalizedStringResource("Fetches new mail for every account now.", table: "ShortcutActions"))

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await host.refresh()
        return .result()
    }
}

extension Catalog {
    /// The cached message the identifier names.
    func facts(ofMessage identifier: String) throws -> MailFacts {
        guard let id = EntityID.message(identifier),
            let facts = try host.messageFacts(inThreads: [id.thread]).first(where: { $0.content?.id == id.message })
        else { throw IntentError.gone }
        return facts
    }
}
