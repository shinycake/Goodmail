public import Foundation
import MailCore

/// Which of the sidebar's sections the reader folded, kept on this device: how much of the sidebar a window shows
/// suits the device, as the window's own size does.
public struct FoldedSections {
    static let key = "sidebarFoldedSections"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isFolded(_ section: MailboxesViewModel.Section) -> Bool {
        folded.contains(section.foldingKey)
    }

    func set(_ section: MailboxesViewModel.Section, folded isFolded: Bool) {
        var keys = folded
        if isFolded { keys.insert(section.foldingKey) } else { keys.remove(section.foldingKey) }
        defaults.set(keys.sorted(), forKey: Self.key)
    }

    private var folded: Set<String> { Set(defaults.stringArray(forKey: Self.key) ?? []) }
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
