import MailCore

extension SceneCoordinator {
    /// Goes where a Home Screen quick action asks. One naming an account that is gone does nothing.
    func perform(_ action: QuickAction) {
        switch action {
        case .newMessage:
            guard let account = model.accounts.first else { return }
            handle(.compose(Draft(accountID: account.id)))
        case .search:
            handle(.search(SearchQuery(terms: [])))
        case .unread:
            handle(.search(SearchQuery(terms: [.unread])))
        case .draft(let id):
            handle(.draft(id))
        case .inbox(let id):
            guard model.accounts.contains(where: { $0.id == id }) else { return }
            handle(.mailbox(Mailbox(labelID: SystemLabel.inbox, accountID: id)))
        }
    }
}
