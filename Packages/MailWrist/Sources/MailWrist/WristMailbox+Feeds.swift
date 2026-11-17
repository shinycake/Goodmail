import MailCore

extension WristSnapshot {
    /// The Inbox the watch shows from its two feeds (ADR-023): the iPhone's snapshot and the watch's own, of the
    /// accounts it reads itself.
    ///
    /// - The accounts, their order and colors are the iPhone's.
    /// - A direct account's rows and unread count come from the watch's own feed; a relayed account's from the
    ///   iPhone's.
    /// - The iPhone's extras are laid over the watch's rows: pins set, threads asleep or muted on the iPhone hidden,
    ///   and the accounts outside the Focus hidden. The iPhone's own rows already show them.
    /// - A pinned row the watch doesn't hold is taken from the iPhone's snapshot.
    /// - Pinned first, then newest first, at most `rowLimit` rows.
    ///
    /// With no own feed, or no direct account, it is the iPhone's snapshot as it is.
    static func merged(
        phone: WristSnapshot, own: WristSnapshot?, sources: [AccountID: WristAccountSource], extras: WristExtras?
    ) -> WristSnapshot {
        let direct = Set(sources.filter { $0.value == .direct }.keys)
        guard let own, !direct.isEmpty else { return phone }
        let extras = extras ?? WristExtras()
        let shown = { (id: ThreadSummary.ID) in
            extras.focus.map { $0.contains(id.accountID) } ?? true
                && !extras.asleep.contains(id) && !extras.muted.contains(id)
        }
        let ownRows = own.rows.filter { direct.contains($0.id.accountID) && shown($0.id) }.map { row in
            var row = row
            row.isPinned = extras.pinned.contains(row.id)
            return row
        }
        let held = Set(ownRows.map(\.id))
        let phoneRows = phone.rows.filter { row in
            guard direct.contains(row.id.accountID) else { return true }
            return row.isPinned && !held.contains(row.id)
        }
        let newestFirst = (ownRows + phoneRows).sorted { $0.date > $1.date }
        var merged = phone
        merged.rows = Array(
            (newestFirst.filter(\.isPinned) + newestFirst.filter { !$0.isPinned }).prefix(Self.rowLimit))
        merged.accounts = phone.accounts.map { account in
            guard direct.contains(account.id) else { return account }
            var account = account
            let inFocus = extras.focus.map { $0.contains(account.id) } ?? true
            account.unread = inFocus ? own.account(account.id)?.unread ?? 0 : 0
            return account
        }
        return merged
    }
}
