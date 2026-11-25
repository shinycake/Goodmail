public import Foundation
import MailCore
public import Observation

/// Which of the sidebar's sections the reader folded, kept on this device: how much of the sidebar a window shows
/// suits the device, as the window's own size does. Every window's sidebar reads the one store through Observation,
/// so a section folded in one window folds in the others at once, and their ⌘1 to ⌘9 follow.
@Observable
public final class FoldedSections {
    /// The app's store, which every window shares.
    public static let shared = FoldedSections()
    static let key = "sidebarFoldedSections"

    /// The folded sections' `foldingKey`s, as stored.
    private var keys: Set<String>
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keys = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func isFolded(_ section: MailboxesViewModel.Section) -> Bool {
        keys.contains(section.foldingKey)
    }

    /// The reader folded or unfolded `section`. Stored as a sorted list of keys.
    func set(_ section: MailboxesViewModel.Section, folded isFolded: Bool) {
        var keys = keys
        if isFolded { keys.insert(section.foldingKey) } else { keys.remove(section.foldingKey) }
        guard keys != self.keys else { return }
        self.keys = keys
        defaults.set(keys.sorted(), forKey: Self.key)
    }
}

extension MailboxesViewModel.Section {
    /// What the section is kept under, and its header's accessibility identifier: an account's by its ID, which
    /// outlives a new address or color.
    var foldingKey: String {
        switch self {
        case .mailboxes: "mailboxes"
        case .smartMailboxes: "smartMailboxes"
        case .labels: "labels"
        case .account(let account): "account.\(account.id.rawValue)"
        }
    }
}

extension MailboxesViewModel.Group {
    /// The unread threads in every row of the group, which its header shows while the group is folded. Snoozed and
    /// Scheduled count what waits, not what is unread. Starred is left out, as it mostly repeats the Inbox's and
    /// labels' threads.
    public var unread: Int {
        items.filter(\.addsToHeaderCount).map(\.nestedCount).reduce(0, +)
    }
}

extension MailboxesViewModel.Item {
    fileprivate var addsToHeaderCount: Bool {
        switch destination {
        case .mailbox(let mailbox): mailbox.labelID != SystemLabel.starred
        case .scheduled, .snoozed: false
        case .folder, .smart: true
        }
    }
}
