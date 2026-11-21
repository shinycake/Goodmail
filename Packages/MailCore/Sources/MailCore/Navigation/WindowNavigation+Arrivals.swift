/// Where a route asked of the window takes it (R1, R2, R5): a conversation in the place of the one read, another list,
/// search, a count of picked rows, or a screen presented over the window, which moves nothing.
extension WindowNavigation {
    /// The rows a conversation was opened from, kept for as long as it is read.
    struct Trail: Equatable, Sendable {
        let thread: ThreadSummary.ID
        let rows: [ThreadSummary.ID]
    }

    mutating func go(to route: Route, in context: Context) -> [Effect] {
        switch route {
        case .thread(let thread, let mailbox):
            // The one read already changes nothing (R2), and a message window reads only its own.
            guard state.layout == .viewer, state.reading?.thread != thread else { return [] }
            return [.lookUp(thread, in: mailbox)]
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
            move { $0.closeReader() }
            return [.showPicked(count)]
        case .newWindow, .compose, .draft, .answer, .changeLabels, .move, .newSmartMailbox, .editSmartMailbox,
            .settings, .signInAgain:
            return [.present(route)]
        }
    }

    /// Reads `summary` in `mailbox`, opened from a list showing `rows`, in the place of any conversation read before
    /// (R1). The one read already stays as it is (R2).
    mutating func open(_ summary: ThreadSummary, in mailbox: Mailbox, from rows: [ThreadSummary.ID]) {
        guard state.layout == .viewer, state.reading?.thread != summary.id else { return }
        move { $0.read(Reading(summary.id, in: mailbox)) }
        found = summary
        trail = Trail(thread: summary.id, rows: rows)
    }

    /// Shows `list` beside the mailboxes. A narrow window shows the list alone, closing the reader over it; a wide one
    /// keeps the conversation read beside it, and shows the list's column. The category and filter stay.
    private mutating func show(_ list: WindowState.List, in context: Context) -> [Effect] {
        guard state.layout == .viewer else { return [] }
        move { state in
            state.list = list
            switch context.arrangement {
            case .stack: state.place = .list(reading: nil)
            case .columns: state.place = .list(reading: state.reading)
            }
        }
        return context.arrangement == .columns ? [.showList] : []
    }

    /// Begins search over the list shown when it is a mailbox's, else over the Inbox's, shown as `show(_:in:)` shows
    /// a list; in place of another list, the Inbox shows alone. The rows the reader goes on in change either way.
    private mutating func search(_ query: SearchQuery, in context: Context) -> [Effect] {
        guard state.layout == .viewer else { return [] }
        let list: WindowState.List =
            switch state.list {
            case .mailbox: state.list
            case .scheduled, .snoozed, .smart: .mailbox(.inbox)
            }
        if list != state.list { move { $0.closeReader() } }
        let shown = show(list, in: context)
        departure = nil
        return shown + [.beginSearch(query)]
    }
}
