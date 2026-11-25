import Foundation
public import MailCore
public import Observation

/// The list of mailboxes, each with its unread count. With one account: the standard mailboxes, with Snoozed while
/// a thread sleeps and Scheduled while a message waits, then the user's labels. With several: the standard mailboxes
/// blending every account, then each account's own standard mailboxes and labels, as Apple Mail lists them.
@Observable
public final class MailboxesViewModel {
    /// Where a row leads.
    nonisolated public enum Destination: Hashable, Sendable {
        case mailbox(Mailbox)
        /// The messages waiting to be sent later.
        case scheduled
        /// The threads snoozed out of the Inbox.
        case snoozed
        /// A step of nested labels' paths that is no label itself, which only holds them.
        case folder(path: String, accountID: AccountID)
        /// A smart mailbox, which no drop goes to (`MailDrop`).
        case smart(SmartMailbox.ID)
    }

    /// A group of rows, under its own header.
    nonisolated public enum Section: Hashable, Sendable {
        /// The standard mailboxes, spanning every account.
        case mailboxes
        /// The reader's smart mailboxes, after the standard ones.
        case smartMailboxes
        /// The only account's labels.
        case labels
        /// One of several accounts: its own standard mailboxes, then its labels.
        case account(Account)
    }

    nonisolated public struct Group: Equatable, Sendable {
        public let section: Section
        /// The rows at the top of the group.
        public let items: [Item]
        /// The rows nested in a row, by its destination: the labels under a label or folder.
        public var children: [Destination: [Item]] = [:]
    }

    nonisolated public struct Item: Hashable, Identifiable, Sendable {
        public var id: Destination { destination }
        public let destination: Destination
        public let title: String
        public let symbol: String
        /// The number beside it: unread threads, or threads or messages waiting. Zero shows none.
        public let count: Int
        /// `count` with the unread threads of the labels nested in it, shown while they are folded away.
        public let nestedCount: Int
        /// Whether labels are nested in it, so it folds.
        public var isParent = false
        /// `#rrggbb` for a user label with a color.
        public let color: String?
    }

    public private(set) var directory = MailboxDirectory()
    /// How the rows fold under section headers: not at all in the list of mailboxes, and in a sidebar as kept in the
    /// store every window's sidebar shares.
    enum Folding {
        case list
        case sidebar(FoldedSections)
    }

    /// Whether this is a sidebar's model, whose sections fold, or the list of mailboxes'. The list showing the model
    /// takes its style from it.
    @ObservationIgnored let folding: Folding
    /// The rows with labels nested in them that the reader folded away, which the list shows folded and ⌘1 to ⌘9
    /// leave out. They last as long as this model: a window rebuilt for another width unfolds them again. Changed
    /// only by `fold(_:folded:)`.
    private(set) var foldedRows: Set<Destination> = []
    /// The smart mailboxes, with their unread counts.
    public private(set) var smartDirectory = SmartMailboxDirectory()
    /// What every account's mailboxes wear, or the only account's color.
    public let theme: Theme

    @ObservationIgnored private let directoryStream: () -> AsyncThrowingStream<MailboxDirectory, any Error>
    @ObservationIgnored private let smartDirectoryStream: () -> AsyncThrowingStream<SmartMailboxDirectory, any Error>
    @ObservationIgnored let navigate: (Route) -> Void
    /// Told when the labels or smart mailboxes, which name lists, change, as the window's title names its list.
    @ObservationIgnored public var namesChanged: (() -> Void)?
    @ObservationIgnored let accounts: [Account]
    /// Carries out what a drop on a row asks for, as the menus' actions do; `nil` where mail can't be changed.
    @ObservationIgnored let actions: MailActions?
    /// What changes an account's labels at its service.
    @ObservationIgnored let labelEditor: (AccountID) -> LabelEditor?
    /// What renames and deletes smart mailboxes; `nil` where they can't be changed.
    @ObservationIgnored let smartMailboxStore: SmartMailboxStore?

    public init(
        accounts: [Account],
        directory: @escaping () -> AsyncThrowingStream<MailboxDirectory, any Error>,
        smartMailboxes: @escaping () -> AsyncThrowingStream<SmartMailboxDirectory, any Error> = {
            AsyncThrowingStream { $0.finish() }
        },
        navigate: @escaping (Route) -> Void = { _ in },
        labelEditor: @escaping (AccountID) -> LabelEditor? = { _ in nil },
        smartMailboxStore: SmartMailboxStore? = nil,
        actions: MailActions? = nil,
        combinedTheme: CombinedTheme = Preferences.combinedTheme,
        style: MailboxesViewController.Style = .list,
        foldedSections: FoldedSections = .shared
    ) {
        folding =
            switch style {
            case .list: .list
            case .sidebar: .sidebar(foldedSections)
            }
        directoryStream = directory
        smartDirectoryStream = smartMailboxes
        self.smartMailboxStore = smartMailboxStore
        self.navigate = navigate
        self.accounts = accounts
        self.labelEditor = labelEditor
        self.actions = actions
        theme = Theme(accountID: nil, among: accounts, combined: combinedTheme)
    }

    /// What a section's icons wear: an account's own color under its address, and the list's theme on the rows that
    /// blend every account or belong to the only one.
    public func theme(of section: Section) -> Theme {
        switch section {
        case .account(let account): .account(account.color)
        case .mailboxes, .smartMailboxes, .labels: theme
        }
    }

    /// The groups to show, leaving out any with no rows.
    public var groups: [Group] {
        let mailboxes = Group(section: .mailboxes, items: standardItems)
        guard accounts.count > 1 else {
            return [mailboxes, smartGroup, labelGroup(.labels, labels: directory.labels)].filter { !$0.items.isEmpty }
        }
        return [mailboxes, smartGroup].filter { !$0.items.isEmpty }
            + accounts.map { account in
                let own = Mailbox.standard(of: account.id).map { item(for: $0, color: nil) }
                let group = labelGroup(
                    .account(account), labels: directory.labels.filter { $0.mailbox.accountID == account.id })
                return Group(section: group.section, items: own + group.items, children: group.children)
            }
    }

    /// The labels as a tree: each with the labels nested in it, under folders where a step of a path is no label.
    private func labelGroup(_ section: Section, labels: [MailboxDirectory.Label]) -> Group {
        var children: [Destination: [Item]] = [:]
        func items(_ nodes: [LabelTree.Node], account: AccountID) -> [Item] {
            nodes.map { node in
                let nested = items(node.children, account: account)
                let nestedUnread = nested.map(\.nestedCount).reduce(0, +)
                let row =
                    node.label.map {
                        item(for: $0.mailbox, color: $0.color, title: node.name, nestedUnread: nestedUnread)
                    }
                    ?? Item(
                        destination: .folder(path: node.path, accountID: account), title: node.name,
                        symbol: "folder", count: 0, nestedCount: nestedUnread, color: nil)
                guard !nested.isEmpty else { return row }
                children[row.destination] = nested
                var parent = row
                parent.isParent = true
                return parent
            }
        }
        // Every label belongs to an account, the one the group lists.
        guard let account = labels.first?.mailbox.accountID else { return Group(section: section, items: []) }
        let roots = items(LabelTree(labels).roots, account: account)
        return Group(section: section, items: roots, children: children)
    }

    /// The standard mailboxes, with Snoozed after Starred while a thread sleeps and Scheduled after Drafts while a
    /// message waits.
    private var standardItems: [Item] {
        var items = Mailbox.standard.map { item(for: $0, color: nil) }
        if directory.snoozedCount > 0, let starred = items.firstIndex(where: { $0.destination == .mailbox(.starred) }) {
            let snoozed = Item(
                destination: .snoozed,
                title: String(
                    localized: "Snoozed", table: "Mailboxes", bundle: .module,
                    comment: "Mailbox: threads snoozed until later"),
                symbol: "moon.zzz", count: directory.snoozedCount, nestedCount: directory.snoozedCount, color: nil)
            items.insert(snoozed, at: starred + 1)
        }
        if directory.scheduledCount > 0, let drafts = items.firstIndex(where: { $0.destination == .mailbox(.drafts) }) {
            let scheduled = Item(
                destination: .scheduled,
                title: String(
                    localized: "Scheduled", table: "Mailboxes", bundle: .module,
                    comment: "Mailbox: messages waiting to be sent later"),
                symbol: "clock", count: directory.scheduledCount, nestedCount: directory.scheduledCount, color: nil)
            items.insert(scheduled, at: drafts + 1)
        }
        return items
    }

    /// `title` in place of the mailbox's own, as a nested label's last step; `nestedUnread` the unread threads of the
    /// labels nested in it.
    private func item(for mailbox: Mailbox, color: String?, title: String? = nil, nestedUnread: Int = 0) -> Item {
        let count = mailbox.showsUnreadCount ? directory.unreadCounts[mailbox] ?? 0 : 0
        return Item(
            destination: .mailbox(mailbox), title: title ?? mailbox.title(labels: directory.labels),
            symbol: mailbox.symbol, count: count, nestedCount: count + nestedUnread, color: color)
    }

    /// Follows the store until the calling task is cancelled. A failure leaves the last directory in place.
    public func observe() async {
        async let smart: Void = followSmartMailboxes()
        do {
            for try await directory in directoryStream() {
                let renamed = directory.labels != self.directory.labels
                self.directory = directory
                if renamed { namesChanged?() }
            }
        } catch {}
        await smart
    }

    private func followSmartMailboxes() async {
        do {
            for try await directory in smartDirectoryStream() {
                let renamed = directory.mailboxes != smartDirectory.mailboxes
                smartDirectory = directory
                if renamed { namesChanged?() }
            }
        } catch {}
    }

    /// The accounts New Label can make a label in, in the list's order.
    var labelAccounts: [Account] {
        accounts.filter { labelEditor($0.id) != nil }
    }

    /// The user label a row shows, which can be renamed and deleted; `nil` for the standard mailboxes.
    func label(at destination: Destination) -> MailboxDirectory.Label? {
        guard case .mailbox(let mailbox) = destination, mailbox.accountID != nil else { return nil }
        return directory.labels.first { $0.mailbox == mailbox }
    }

    /// How many of the account's labels are nested in `label`, which deleting it deletes too.
    func nestedLabelCount(in label: MailboxDirectory.Label) -> Int {
        label.mailbox.accountID.map { labelCount(under: label.name, account: $0) } ?? 0
    }

    /// How many of `account`'s labels have paths under `path`, as `Extra/Unsubscribed` does under `Extra`.
    func labelCount(under path: String, account: AccountID) -> Int {
        directory.labels.count { $0.mailbox.accountID == account && $0.name.hasPrefix(path + "/") }
    }

    public func open(_ destination: Destination) {
        switch destination {
        case .mailbox(let mailbox): navigate(.mailbox(mailbox))
        case .scheduled: navigate(.scheduled)
        case .snoozed: navigate(.snoozed)
        case .smart(let id): navigate(.smartMailbox(id))
        case .folder: break
        }
    }

    public func openSettings() {
        navigate(.settings(.main))
    }

    /// A new message from the first account. The composer's From menu changes it.
    public func compose() {
        guard let account = accounts.first else { return }
        navigate(.compose(Draft(accountID: account.id)))
    }
}

/// What the reader folded: a section under its header in a sidebar, kept in `FoldedSections` for every window, and a
/// row's nested labels, kept in this model (`foldedRows`). The list's rows and ⌘1 to ⌘9 are both read from this, and
/// the reader folding something is the only change to it.
extension MailboxesViewModel {
    /// How the list showing this model looks: a sidebar, or the list of mailboxes.
    public var style: MailboxesViewController.Style {
        switch folding {
        case .list: .list
        case .sidebar: .sidebar
        }
    }

    /// Whether `section` folds under a header row: in a sidebar, every section but the standard mailboxes.
    func foldsUnderHeader(_ section: Section) -> Bool {
        sectionStore(section) != nil
    }

    /// Whether `section`'s rows are folded away under its header.
    func isFolded(_ section: Section) -> Bool {
        sectionStore(section)?.isFolded(section) ?? false
    }

    /// Whether the labels nested in `destination`'s row are folded away.
    func isFolded(_ destination: Destination) -> Bool {
        foldedRows.contains(destination)
    }

    /// The reader folded or unfolded `row`: a section's header, or a row with labels nested in it.
    func fold(_ row: SidebarRow, folded: Bool) {
        switch row {
        case .header(let section):
            sectionStore(section)?.set(section, folded: folded)
        case .mailbox(let item):
            guard isFolded(item.destination) != folded else { return }
            if folded { foldedRows.insert(item.destination) } else { foldedRows.remove(item.destination) }
        }
    }

    /// Where `section`'s folding is kept, if it folds.
    private func sectionStore(_ section: Section) -> FoldedSections? {
        guard case .sidebar(let store) = folding, section != .mailboxes else { return nil }
        return store
    }
}
