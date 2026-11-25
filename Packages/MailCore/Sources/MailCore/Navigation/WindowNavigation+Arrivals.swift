/// Where a route asked of the window takes it (R1, R2, R5): a conversation in the place of the one read, another list,
/// search, a count of picked rows, or a screen presented over the window, which moves nothing.
extension WindowNavigation {
    /// The conversation read, as it was opened: from which list, the rows it listed then, and the row itself when the
    /// window had it. Replaced whole each time a conversation opens, kept with the conversation read (`Course`), and
    /// counted only while the window reads it from that list, so where the reader goes after it never follows another
    /// list's rows.
    struct Opened: Equatable, Sendable {
        /// A list a conversation opens from: a list's own rows, or search's over them.
        struct From: Equatable, Sendable {
            let list: WindowState.List
            let searching: Bool
        }

        let from: From
        let rows: [ThreadSummary.ID]
        let row: ThreadSummary?
    }

    /// The conversation a lookup is under way for: where the route reads it, and where the route came from, which
    /// decides where it shows once found.
    public struct Awaited: Equatable, Sendable {
        public let reading: Reading
        public let source: RouteSource
    }

    /// Goes where `route`, from `source`, asks.
    mutating func go(to route: Route, from source: RouteSource = .window, in context: Context) -> [Effect] {
        if let presentation = Presentation(route, from: source) { return [.present(presentation)] }
        switch route {
        case .thread(let thread, let mailbox):
            // The one read already changes nothing (R2), and a message window reads only its own.
            guard state.layout == .viewer, state.reading?.thread != thread else {
                endLookUp()
                return []
            }
            beginLookUp(Awaited(reading: Reading(thread, in: mailbox), source: source))
            return [.lookUp(thread)]
        case .mailbox(let mailbox):
            return show(.mailbox(mailbox), in: context)
        case .scheduled:
            return show(.scheduled, in: context)
        case .snoozed:
            return show(.snoozed, in: context)
        case .smartMailbox(let id):
            return show(.smart(id), in: context)
        case .search(let query):
            return search(query, in: context)
        case .selection(let count):
            // Only beside the list: a narrow window shows the list alone, which shows its own pick.
            guard state.layout == .viewer, context.arrangement == .columns else { return [] }
            // Another pick moves the window on, though the reader may be closed already (R9). A pick of none doesn't:
            // after a pick is put away the list reads the row after it, which a pick of none closes and so moves the
            // window on anyway, or picks nothing, so none then is only the put-away rows leaving.
            if count > 0 { endWayBack() }
            move { $0.closeReader() }
            return [.showPicked(count)]
        case .compose, .draft, .answer, .changeLabels, .move, .newSmartMailbox, .editSmartMailbox, .settings,
            .signInAgain, .newWindow, .receiveTransfer:
            // Presented above.
            return []
        }
    }

    /// Reads `summary`, opened from a list showing `rows`, in the place of any conversation read before (R1), when it
    /// is what the lookup under way asked for; an answer for one the window has moved on from opens nothing. One from
    /// inside reads over the list as it is (R5); one from outside shows in a list that holds it (R4).
    mutating func open(
        _ summary: ThreadSummary, from rows: [ThreadSummary.ID], searching: Bool, in context: Context
    ) {
        guard let pending, pending.reading.thread == summary.id else { return }
        endLookUp()
        switch pending.source {
        case .window:
            let opening = Opened(from: source(searching: searching), rows: rows, row: summary)
            move(opening: opening) { $0.read(pending.reading) }
        case .outside:
            reveal(summary, routedTo: pending.reading.mailbox, from: rows, in: context)
        }
    }

    /// Shows `list` beside the mailboxes, with nothing read, in either arrangement, as Mail does. The category and
    /// filter stay. A wide window shows the list's column.
    mutating func show(_ list: WindowState.List, in context: Context) -> [Effect] {
        guard state.layout == .viewer else { return [] }
        // A list asked for again ends a lookup under way too.
        endLookUp()
        move {
            $0.list = list
            $0.place = .list(reading: nil)
        }
        return context.arrangement == .columns ? [.showList] : []
    }

    /// Begins search over the list shown when it is a mailbox's, else over the Inbox's, shown as `show(_:in:)` shows
    /// a list.
    private mutating func search(_ query: SearchQuery, in context: Context) -> [Effect] {
        guard state.layout == .viewer else { return [] }
        let list: WindowState.List =
            switch state.list {
            case .mailbox: state.list
            case .scheduled, .snoozed, .smart: .mailbox(.inbox)
            }
        let shown = show(list, in: context)
        endWayBack()
        return shown + [.beginSearch(query)]
    }
}
