import Foundation
public import MailCore

/// Where Move offers to send threads the reader sees in one mailbox: the system places first, then the account's
/// labels. The mailbox they are in isn't offered.
public final class MoveViewModel {
    public struct Choice: Equatable, Identifiable {
        public let destination: MoveDestination
        public let name: String
        let symbol: String
        /// A user label's `#rrggbb` color, when the user picked one.
        let color: String?
        public var id: MoveDestination { destination }
    }

    /// Inbox, Archive, Spam and Trash.
    public let places: [Choice]
    /// The account's visible user labels, in its order. None when the threads come from several accounts, since
    /// each account has its own labels.
    public let labels: [Choice]
    /// Makes a new label to move the threads to; `nil` when they come from several accounts, like `labels`.
    let editor: LabelEditor?
    private let threads: [ThreadSummary.ID]
    private let mailbox: Mailbox
    private let actions: MailActions?

    /// `labels` are those of the threads' account (`account(of:)`), and `editor` gives what changes an account's.
    public init(
        threads: [ThreadSummary.ID], from mailbox: Mailbox, labels: [MailLabel],
        editor: (AccountID) -> LabelEditor? = { _ in nil }, actions: MailActions?
    ) {
        self.threads = threads
        self.mailbox = mailbox
        self.actions = actions
        let current = MoveDestination(mailbox)
        let archive = String(
            localized: "move.archive", defaultValue: "Archive", table: "Move", bundle: .module,
            comment: "Move destination: out of the Inbox, with no label")
        places = [
            Choice(
                destination: .inbox, name: Mailbox.inbox.title(labels: []), symbol: Mailbox.inbox.symbol, color: nil),
            Choice(destination: .archive, name: archive, symbol: "archivebox", color: nil),
            Choice(destination: .spam, name: Mailbox.spam.title(labels: []), symbol: Mailbox.spam.symbol, color: nil),
            Choice(
                destination: .trash, name: Mailbox.trash.title(labels: []), symbol: Mailbox.trash.symbol, color: nil),
        ]
        .filter { $0.destination != current }
        let account = Self.account(of: threads)
        self.labels =
            account == nil
            ? []
            : labels.filter { $0.kind == .user && !$0.isHidden }.map(Self.choice).filter { $0.destination != current }
        self.editor = account.flatMap(editor)
    }

    /// The one account the threads come from, whose labels Move offers; `nil` when they come from several, since each
    /// account has its own labels.
    public static func account(of threads: [ThreadSummary.ID]) -> AccountID? {
        let accounts = Set(threads.map(\.accountID))
        return accounts.count == 1 ? accounts.first : nil
    }

    private static func choice(_ label: MailLabel) -> Choice {
        Choice(destination: .label(label.id), name: label.name, symbol: "tag", color: label.color)
    }

    /// Moves the threads to a label just made for them.
    public func move(toNew label: MailLabel) {
        move(to: Self.choice(label))
    }

    /// Moves the threads to `choice`, with an undo toast.
    public func move(to choice: Choice) {
        actions?.move(threads, to: choice.destination, named: choice.name, from: mailbox)
    }
}
