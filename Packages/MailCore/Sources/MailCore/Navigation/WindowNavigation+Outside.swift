/// Where a route from outside the window takes it: the window is uncovered first (R3), a conversation shows in a list
/// that holds it (R4), and one that is gone is said to be (R10).
extension WindowNavigation {
    /// Goes where `route`, from outside, asks, uncovering the window first, which ends search, so a conversation
    /// opened now is opened from the list's own rows. Settings, which comes up over whatever is up, uncovers nothing:
    /// dismissing an open Settings only to show it again would lose its page.
    mutating func arrive(at route: Route, in context: Context) -> [Effect] {
        if case .settings = route { return go(to: route, from: .outside, in: context) }
        return [.uncover] + go(to: route, from: .outside, in: context)
    }

    /// The window comes up for `route` over the state it restored (`Event.launched`). Nothing covers a window not
    /// yet built, so nothing is uncovered; a restored conversation the route doesn't open closes first, and a
    /// restored message window becomes a viewer for it.
    mutating func launch(for route: Route, in context: Context) -> [Effect] {
        if case .thread(let thread, _) = route, state.reading?.thread != thread { state.closeReader() }
        return go(to: route, from: .outside, in: context)
    }

    /// Reads `summary`, which a route from outside asked for in `mailbox`, in a list that holds it (R4): the list on
    /// show when it lists it, else the route's mailbox when that holds it, else the one standard mailbox its labels
    /// put it in, so one archived or trashed since the alert is read where it is now. An Inbox shows the
    /// conversation's category. `rows` are the list on show's, which are the conversation's trail only while that
    /// list and category stay.
    mutating func reveal(
        _ summary: ThreadSummary, routedTo mailbox: Mailbox, from rows: [ThreadSummary.ID], in context: Context
    ) {
        var next = state
        if !rows.contains(summary.id), !next.list.holds(summary) {
            next.list = .mailbox(mailbox.contains(summary) ? mailbox : .holding(summary.labelIDs))
        }
        if next.list.isInbox {
            next.category =
                context.unsortedInboxes.contains(summary.id.accountID) ? .primary : InboxCategory(of: summary)
        }
        next.read(Reading(summary.id, in: next.list.readingMailbox ?? .holding(summary.labelIDs)))
        let trail = next.list == state.list && next.category == state.category ? rows : []
        opened = Opened(
            thread: summary.id, from: Opened.From(list: next.list, searching: false), rows: trail, row: summary)
        state = next
    }

    /// An arrival's conversation can't be shown (R10): the window shows the Inbox, reading nothing, and says why.
    mutating func showInbox(saying notice: Notice, in context: Context) -> [Effect] {
        show(.mailbox(.inbox), in: context) + [.say(notice)]
    }
}

extension WindowState.List {
    /// Whether the list holds `thread` by what it is, rather than by the rows it has loaded: a mailbox's list holds
    /// every conversation its labels put there. Scheduled, Snoozed and a smart mailbox hold only the rows they list.
    fileprivate func holds(_ thread: ThreadSummary) -> Bool {
        guard case .mailbox(let mailbox) = self else { return false }
        return mailbox.contains(thread)
    }

    /// Whether the list is an Inbox, of every account or of one, which shows one category at a time.
    fileprivate var isInbox: Bool {
        guard case .mailbox(let mailbox) = self else { return false }
        return mailbox.labelID == SystemLabel.inbox
    }
}
