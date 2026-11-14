import MailCore

/// The account's folders as Goodmail's labels. IMAP files each message in one folder, so the folder gives it its
/// one label: a role folder its `SystemLabel`, Archive none (archived mail is only in All Mail), and any other folder
/// its wire name. STARRED and UNREAD are flags, so they span folders.
struct Folders: Sendable {
    /// The folders that hold messages.
    let all: [IMAPMailbox]

    init(_ mailboxes: [IMAPMailbox]) {
        let selectable = mailboxes.filter(\.isSelectable)
        // Servers without special-use attributes (RFC 6154), and iCloud for all but Sent and Trash, leave roles
        // unmarked. A role no folder claims goes to the first folder with a usual name for it.
        var claimed = Set(selectable.compactMap(\.role))
        all = selectable.map { folder in
            guard folder.role == nil, let role = Self.role(named: folder.wireName), !claimed.contains(role)
            else { return folder }
            claimed.insert(role)
            var named = folder
            named.role = role
            return named
        }
    }

    /// The role a folder's name gives it, as iCloud, Exchange, Dovecot, Yahoo and the rest name their role
    /// folders. Courier and some Dovecot setups keep every folder inside INBOX, as `INBOX.Sent`.
    private static func role(named wireName: String) -> IMAPMailbox.Role? {
        let name = wireName.lowercased()
        let top = ["inbox.", "inbox/"].first(where: name.hasPrefix).map { String(name.dropFirst($0.count)) } ?? name
        return roles[top]
    }

    private static let roles: [String: IMAPMailbox.Role] = [
        "sent messages": .sent, "sent": .sent, "sent items": .sent, "sent mail": .sent,
        "drafts": .drafts, "draft": .drafts,
        "deleted messages": .trash, "trash": .trash, "deleted items": .trash, "deleted": .trash,
        "junk": .junk, "spam": .junk, "junk e-mail": .junk, "junk email": .junk, "bulk mail": .junk,
        "archive": .archive, "archives": .archive,
    ]

    static func label(of folder: IMAPMailbox) -> String? {
        switch folder.role {
        case .inbox: SystemLabel.inbox
        case .sent: SystemLabel.sent
        case .drafts: SystemLabel.draft
        case .trash: SystemLabel.trash
        case .junk: SystemLabel.spam
        case .archive: nil
        case nil: folder.wireName
        }
    }

    func contains(_ wireName: String) -> Bool {
        all.contains { $0.wireName == wireName }
    }

    func label(ofFolderNamed wireName: String) -> String? {
        all.first { $0.wireName == wireName }.flatMap(Self.label)
    }

    /// The folder a message moves to for `label`: Archive for none.
    func folder(for label: String?) -> IMAPMailbox? {
        guard let label else { return all.first { $0.role == .archive } }
        return all.first { Self.label(of: $0) == label }
    }

    /// The folders that hold `label`'s threads, and the flag that marks them there. `nil` is All Mail.
    func search(for label: String?) -> (folders: [IMAPMailbox], flag: IMAPSearch.Flag?) {
        switch label {
        case nil: (allMail, nil)
        case SystemLabel.starred: (allMail, .flagged)
        case SystemLabel.unread: (allMail, .unseen)
        case let label?: (all.filter { Self.label(of: $0) == label }, nil)
        }
    }

    /// Every folder outside Spam and Trash.
    private var allMail: [IMAPMailbox] {
        all.filter { $0.role != .junk && $0.role != .trash }
    }

    var labels: [MailLabel] {
        let folders = all.compactMap { folder in
            Self.label(of: folder).map {
                MailLabel(id: $0, name: folder.name, kind: folder.role == nil ? .user : .system)
            }
        }
        return folders + [
            MailLabel(id: SystemLabel.starred, name: "Starred", kind: .system),
            MailLabel(id: SystemLabel.unread, name: "Unread", kind: .system),
        ]
    }

    /// The labels a message has in `folder` with these IMAP flags.
    static func labelIDs(folderLabel: String?, flags: Set<String>) -> Set<String> {
        var labels = Set([folderLabel].compactMap(\.self))
        if flags.contains(#"\Flagged"#) { labels.insert(SystemLabel.starred) }
        if !flags.contains(#"\Seen"#) { labels.insert(SystemLabel.unread) }
        return labels
    }
}
