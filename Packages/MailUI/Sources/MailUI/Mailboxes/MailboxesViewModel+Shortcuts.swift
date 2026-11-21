import Foundation
import MailCore

/// The rows the number keys reach: ⌘1 to ⌘9 open them, ⌃⌘1 to ⌃⌘9 move the picked conversations to them.
extension MailboxesViewModel {
    /// A row that has a number: where it leads and the name the menu bar gives it.
    struct NumberedRow: Sendable {
        let destination: Destination
        let title: String
    }

    /// The first nine rows the sidebar shows now, folded labels left out (`folded`). With several accounts a row
    /// that every account has, as its Inbox, is named with its account.
    var numberedRows: NumberedRows<NumberedRow> {
        NumberedRows(
            visible: visibleRows,
            isOpenable: { row in
                if case .folder = row.destination { false } else { true }
            })
    }

    /// Every row on show, top to bottom, in the order the sidebar lists them.
    private var visibleRows: [NumberedRow] {
        var rows: [NumberedRow] = []
        for group in groups {
            func append(_ items: [Item]) {
                for item in items {
                    rows.append(NumberedRow(destination: item.destination, title: name(of: item, in: group.section)))
                    guard let nested = group.children[item.destination], !folded.contains(item.destination) else {
                        continue
                    }
                    append(nested)
                }
            }
            append(group.items)
        }
        return rows
    }

    private func name(of item: Item, in section: Section) -> String {
        guard case .account(let account) = section, accounts.count > 1 else { return item.title }
        return String(
            localized: "\(item.title) (\(account.title))", table: "Keyboard", bundle: .module,
            comment: "Menu bar command naming a mailbox of one account among several, as Inbox (me@example.com)")
    }

    /// What ⌘1 to ⌘9 do: open the row, under its name. A number past the last row answers nothing, so its item hides.
    func answer(toOpening shortcut: RowShortcut) -> CommandAnswer {
        guard let row = numberedRows[shortcut] else { return .notHere }
        return .ready(perform: { [self] in open(row.destination) }, title: row.title)
    }

    /// What ⌃⌘1 to ⌃⌘9 do with the picked `threads`: move them to the row, as dropping them on it does, or dim the
    /// item while the row refuses them or nothing is picked.
    func answer(toMoving threads: [DraggedThread], to shortcut: RowShortcut) -> CommandAnswer {
        guard let row = numberedRows[shortcut] else { return .notHere }
        let drop = drop(of: threads, onto: row.destination, adding: false)
        guard !threads.isEmpty, drop != .refused else { return .refused(title: row.title) }
        return .ready(perform: { [self] in perform(drop, of: threads, onto: row.destination) }, title: row.title)
    }
}
