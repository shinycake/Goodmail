import MailCore

/// What a thread action does to one copy of a message. IMAP files each copy in one folder, so the labels that are
/// folders become a move and copies, and STARRED and UNREAD become flags.
struct CopyPlan: Equatable {
    enum Placement: Equatable {
        case stay
        /// To the folder of this label, or Archive for `nil`.
        case move(toLabel: String?)
    }

    var addFlags: Set<String> = []
    var removeFlags: Set<String> = []
    var placement = Placement.stay
    /// Labels whose folders get a copy, as Gmail gives a message a second label.
    var copies: [String] = []

    init(
        addFlags: Set<String> = [], removeFlags: Set<String> = [], placement: Placement = .stay, copies: [String] = []
    ) {
        self.addFlags = addFlags
        self.removeFlags = removeFlags
        self.placement = placement
        self.copies = copies
    }

    /// - A copy in Trash or Spam is held there alone, so a label set holding either puts the copy there.
    /// - Sent and Drafts are where mail was made, not places: their copies only move to Trash.
    /// - A copy whose folder keeps its label stays, and gets a copy in each folder whose label was added.
    /// - Otherwise it moves to the first folder left (the Inbox first), or to Archive when none is.
    init(action: ThreadAction, folderLabel: String?, flags: Set<String>) {
        let after = action.applied(to: Folders.labelIDs(folderLabel: folderLabel, flags: flags))
        if after.contains(SystemLabel.starred) != flags.contains(Self.flagged) {
            if after.contains(SystemLabel.starred) {
                addFlags.insert(Self.flagged)
            } else {
                removeFlags.insert(Self.flagged)
            }
        }
        if after.contains(SystemLabel.unread) == flags.contains(Self.seen) {
            if after.contains(SystemLabel.unread) { removeFlags.insert(Self.seen) } else { addFlags.insert(Self.seen) }
        }

        let folders = after.subtracting([SystemLabel.starred, SystemLabel.unread])
        let held = [SystemLabel.trash, SystemLabel.spam].first(where: folders.contains)
        let places = folders.subtracting([SystemLabel.sent, SystemLabel.draft]).sorted {
            ($0 == SystemLabel.inbox ? 0 : 1, $0) < ($1 == SystemLabel.inbox ? 0 : 1, $1)
        }
        if folderLabel == SystemLabel.sent || folderLabel == SystemLabel.draft {
            if folders.contains(SystemLabel.trash) { placement = .move(toLabel: SystemLabel.trash) }
        } else if let held {
            if folderLabel != held { placement = .move(toLabel: held) }
        } else if let folderLabel, places.contains(folderLabel) {
            copies = places.filter { $0 != folderLabel }
        } else if let first = places.first {
            placement = .move(toLabel: first)
            copies = Array(places.dropFirst())
        } else if folderLabel != nil {
            placement = .move(toLabel: nil)
        }
    }

    static let flagged = #"\Flagged"#
    static let seen = #"\Seen"#
}
