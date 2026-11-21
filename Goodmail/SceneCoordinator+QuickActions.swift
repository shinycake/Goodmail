import MailCore

extension SceneCoordinator {
    /// Where a Home Screen quick action goes. One naming an account that is gone, or a new message with no account to
    /// send from, goes nowhere.
    func route(for action: QuickAction) -> Route? {
        switch action {
        case .newMessage:
            model.accounts.first.map { .compose(Draft(accountID: $0.id)) }
        case .search:
            .search(SearchQuery(terms: []))
        case .unread:
            .search(SearchQuery(terms: [.unread]))
        case .draft(let id):
            .draft(id)
        case .inbox(let id):
            model.accounts.contains { $0.id == id } ? .mailbox(Mailbox(labelID: SystemLabel.inbox, accountID: id)) : nil
        }
    }
}
