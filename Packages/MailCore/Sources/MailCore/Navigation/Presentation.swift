public import Foundation

/// A screen a window presents over or beside what it shows, which moves nothing in it: the routes that aren't places
/// (ADR-011). Where each goes, a sheet or a window of its own, is the window's interaction style's to say (ADR-035).
public enum Presentation: Hashable, Sendable {
    /// The composer, with a new message, reply or forward.
    case compose(Draft)
    /// The composer, finishing the draft that is a thread's newest message; the thread itself when it is no draft,
    /// opened as a route from `source` opens it.
    case draft(ThreadSummary.ID, from: RouteSource = .window)
    /// The composer, answering a thread's newest message.
    case answer(ThreadSummary.ID, Answer)
    /// The label picker for these threads.
    case changeLabels([ThreadSummary.ID])
    /// Where to move these threads, which the reader sees in the mailbox.
    case move([ThreadSummary.ID], from: Mailbox)
    /// The smart mailbox editor with a new box holding what the query finds.
    case newSmartMailbox(SearchQuery)
    /// The smart mailbox editor, changing a box.
    case editSmartMailbox(SmartMailbox.ID)
    /// Accounts and preferences, open at the page.
    case settings(SettingsPage)
    /// The account's sign-in, again.
    case signInAgain(AccountID)
    /// A thread in a window of its own, read from the mailbox.
    case newWindow(ThreadSummary.ID, in: Mailbox)
    /// Accounts from another device, received with the code.
    case receiveTransfer(code: URL)

    /// What `route`, from `source`, presents, or `nil` for a place the window moves to.
    public init?(_ route: Route, from source: RouteSource = .window) {
        switch route {
        case .compose(let draft): self = .compose(draft)
        case .draft(let thread): self = .draft(thread, from: source)
        case .answer(let thread, let answer): self = .answer(thread, answer)
        case .changeLabels(let threads): self = .changeLabels(threads)
        case .move(let threads, let mailbox): self = .move(threads, from: mailbox)
        case .newSmartMailbox(let query): self = .newSmartMailbox(query)
        case .editSmartMailbox(let id): self = .editSmartMailbox(id)
        case .settings(let page): self = .settings(page)
        case .signInAgain(let account): self = .signInAgain(account)
        case .newWindow(let thread, let mailbox): self = .newWindow(thread, in: mailbox)
        case .receiveTransfer(let code): self = .receiveTransfer(code: code)
        case .thread, .selection, .mailbox, .search, .scheduled, .snoozed, .smartMailbox: return nil
        }
    }
}
