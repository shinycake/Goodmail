public import AppIntents
import MailCore

/// The Focus filter Settings offers for Goodmail: while the Focus is on, only the chosen accounts show in the views
/// that blend every account, and only they alert (ADR-012). Choosing none shows every account.
public struct AccountsFocusFilter: SetFocusFilterIntent {
    public static let title: LocalizedStringResource = "Accounts"
    public static let description = IntentDescription("Show and alert only for the chosen accounts.")

    @Parameter(title: "Accounts")
    public var accounts: [AccountEntity]?

    @Dependency private var host: any MailIntentsHost

    public var displayRepresentation: DisplayRepresentation {
        let names = (accounts ?? []).map(\.title)
        return names.isEmpty
            ? DisplayRepresentation(title: "Every Account")
            : DisplayRepresentation(title: "\(names.formatted(.list(type: .and)))")
    }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await host.apply(FocusFilter(showing: accounts))
        return .result()
    }
}

extension FocusFilter {
    /// The filter for the accounts a Focus names: every account when it names none.
    init(showing accounts: [AccountEntity]?) {
        let ids = Set((accounts ?? []).map(\.accountID))
        self = ids.isEmpty ? .everyAccount : .accounts(ids)
    }
}
