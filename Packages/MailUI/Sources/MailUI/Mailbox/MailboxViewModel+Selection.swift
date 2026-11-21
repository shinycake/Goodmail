import MailCore

/// The ways the list's pick changes. A desktop window picks with clicks and keys, which the reader follows; touch
/// reports what the collection view picked, in Select mode or by opening a row, and opens threads itself. Either way
/// the window says which row is read after an action (`MailboxViewController.mark(reading:)`).
extension MailboxViewModel {
    /// The threads' ids as the list shows them, across its sections, top to bottom.
    var rows: [ThreadSummary.ID] { sections.flatMap(\.threads).map(\.id) }

    /// The picked threads, in the list's order.
    var selectedIDs: [ThreadSummary.ID] { selection.ids(in: rows) }

    // MARK: Pointer and keys

    /// A click on `row`, plain or with ⌘ or ⇧.
    func click(_ row: ThreadSummary.ID, _ click: ListSelection.Click) {
        pick(selection.clicking(row, click, in: rows), revealing: true)
    }

    /// ↓ (`offset` 1) or ↑ (-1), with ⇧ when `extending`.
    func move(_ offset: Int, extending: Bool) {
        pick(selection.moving(offset, extending: extending, in: rows), revealing: true)
    }

    /// ⌘A.
    func selectAll() {
        pick(selection.selectingAll(in: rows), revealing: true)
    }

    /// Escape: several drop back to the row they grew from.
    func dropSelection() {
        pick(selection.dropped, revealing: true)
    }

    /// The threads a menu opened on `row` acts on: the whole pick when the row is in it, in the list's order.
    func menuTargets(for row: ThreadSummary.ID) -> [ThreadSummary.ID] {
        let targets = selection.acting(on: row)
        return rows.filter(targets.contains)
    }

    // MARK: Touch

    /// What the collection view picked on touch: in Select mode while `selecting`, otherwise the row it marks as open.
    func picked(_ ids: [ThreadSummary.ID], selecting: Bool) {
        let new: ListSelection =
            selecting ? .several(Set(ids), anchor: nil) : ids.first.map(ListSelection.reading) ?? .none
        pick(new, revealing: false)
    }

    /// Marks `id` as the thread open beside the list, as one opened before the list was built, without opening it again.
    func markReading(_ id: ThreadSummary.ID) {
        pick(.reading(id), revealing: false)
    }

    // MARK: Rows leaving

    /// After the rows changed: rows that left drop out of the pick, and nothing opens, whatever took them away. Where
    /// the reader goes after an action is the window's to say (`mark(reading:)`), and sync or another device never
    /// moves it (R6). A desktop window counts what is left of several beside the list, and nothing once none is.
    func pickAfterRowsChanged() {
        let kept = selection.keeping(rows)
        switch (interaction, kept) {
        case (.desktop, .several(let ids, _)): pick(ids.isEmpty ? .none : kept, revealing: true)
        case (.desktop, _), (.touch, _): pick(kept, revealing: false)
        }
    }
}
