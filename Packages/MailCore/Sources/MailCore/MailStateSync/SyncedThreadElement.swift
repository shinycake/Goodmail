extension ThreadSummary.ID {
    /// The thread's name in the mail state the reader's devices share (ADR-037): its account, a slash, and its thread.
    /// Both are the same on every device, and an account ID never holds a slash, so a thread ID may.
    public var syncedElement: String { accountID.rawValue + "/" + threadID }

    /// The thread `element` names, or `nil` for an element that names none.
    public init?(syncedElement element: String) {
        guard let slash = element.firstIndex(of: "/") else { return nil }
        let account = element[..<slash]
        let thread = element[element.index(after: slash)...]
        guard !account.isEmpty, !thread.isEmpty else { return nil }
        self.init(accountID: AccountID(rawValue: String(account)), threadID: String(thread))
    }
}
