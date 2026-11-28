import MailCore
import Observation

/// What the list follows from the store: the category it shows, when the Inbox is split, and the window.
nonisolated struct ListAsk: Equatable, Sendable {
    let category: InboxCategory?
    let window: ThreadWindow
}

extension MailboxSource {
    /// Whether the list reads its mailbox a window at a time.
    var isWindowed: Bool {
        if case .flat(.whole) = self { return false }
        return true
    }
}

/// The list's window on its mailbox (ADR-045): it reads the newest threads, more as the reader nears their end, and
/// every one for what acts on or filters the whole mailbox.
extension MailboxViewModel {
    /// What the list follows from the store now.
    var ask: ListAsk { ListAsk(category: category, window: window.asked) }

    /// How many rows the list shows.
    var rowCount: Int { sections.reduce(0) { $0 + $1.threads.count } }

    /// The reader was shown row `index`, as it scrolled into sight or as its conversation opened. Near the end of the
    /// rows, the list reads further (`nearEnd`).
    func show(row index: Int) {
        moveWindow { $0.shown(row: index) }
        guard rowCount - index <= ListWindow.lead else { return }
        nearEnd()
    }

    /// The reader nears the end of the rows: the list reads twice as many when the store holds more, or, once it has
    /// listed every thread the store holds, fetches an older page from the service. Nothing while the store's answer
    /// for the window is on its way.
    func nearEnd() {
        guard let reach = listing.reach else { return }
        var widened = false
        moveWindow { widened = $0.nearEnd(reach: reach) }
        if !widened { loadOlder() }
    }

    /// Every thread the list shows, once the store has listed the whole mailbox: what Empty Trash deletes. The list
    /// reads every thread for it, then goes back to its window. `nil` when the wait is cancelled first.
    func everyThread() async -> [ThreadSummary.ID]? {
        defer { letGo(.everyThread) }
        guard await listWhole(for: .everyThread) else { return nil }
        return rows
    }

    /// Select All, on touch or with ⌘A: reads every thread and waits until the store has listed them, keeping them
    /// listed while several stay picked (`pick`). Returns whether they are listed: false when the wait is cancelled,
    /// or the pick ended first, which lets them go.
    func listEveryThreadToSelect() async -> Bool {
        let listed = await listWhole(for: .selectAll)
        if !listed { letGo(.selectAll) }
        return listed
    }

    /// Lets `need` go. Once nothing holds the list whole, its window keeps what the reader reached meanwhile: the
    /// deepest row shown, and what is read or picked, wherever the store's order places them, which a filter's rows
    /// don't say.
    func letGo(_ need: ListWindow.Need) {
        guard window.holds(need) else { return }
        let depth = depthToKeep()
        moveWindow { $0.letGo(need, keeping: depth) }
    }

    /// How many of the store's threads, newest first, it takes to keep the deepest row shown while the list was whole,
    /// and what is read or picked.
    private func depthToKeep() -> Int {
        let rows = rows
        var kept = selection.ids
        if let deepest = window.deepestRowShown, rows.indices.contains(deepest) { kept.insert(rows[deepest]) }
        guard !kept.isEmpty, let last = listing.threads.lastIndex(where: { kept.contains($0.id) }) else { return 0 }
        return last + 1
    }

    /// Whether `ids` are every thread the list shows of the whole mailbox, rather than of its window.
    func showsEvery(_ ids: [ThreadSummary.ID]) -> Bool {
        listing.reach == .whole && ids.count == rowCount
    }

    /// Reads every thread for `need`, and waits until the store has listed them. Returns whether it has: false when
    /// cancelled first, or when `need` was let go meanwhile.
    private func listWhole(for need: ListWindow.Need) async -> Bool {
        // A window that holds the whole mailbox already lists every thread.
        if listing.reach == .whole { return true }
        moveWindow { $0.hold(need) }
        for await wait in Observations({ self.wholeListing(for: need) }) {
            switch wait {
            case .waiting: continue
            case .listed: return true
            case .letGo: return false
            }
        }
        return false
    }

    /// Where a wait for the whole mailbox stands.
    private enum WholeListing: Equatable, Sendable {
        case waiting
        case listed
        /// What needed it let go.
        case letGo
    }

    private func wholeListing(for need: ListWindow.Need) -> WholeListing {
        guard window.isWhole(for: need) else { return .letGo }
        // `moveWindow` makes the list wait whenever it asks for other threads, so an answer now is the whole one.
        return listing.hasAnswered ? .listed : .waiting
    }
}
