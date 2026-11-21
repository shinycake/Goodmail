import MailCore
import Testing

/// The sidebar's rows by number, for ⌘1 to ⌘9 and ⌃⌘1 to ⌃⌘9.
struct RowShortcutTests {
    private func numbered(_ rows: [String], folders: Set<String> = []) -> NumberedRows<String> {
        NumberedRows(visible: rows, isOpenable: { !folders.contains($0) })
    }

    @Test func rowsAreNumberedFromOneInTheOrderShown() {
        let rows = numbered(["Inbox", "Starred", "Sent"])
        #expect(rows[.goTo(1)] == "Inbox")
        #expect(rows[.goTo(3)] == "Sent")
        #expect(rows[.moveTo(2)] == "Starred", "Move To counts the rows as Go To does")
    }

    @Test func aFolderThatOpensNothingTakesNoNumber() {
        let rows = numbered(["Inbox", "Receipts", "Receipts/2026", "Sent"], folders: ["Receipts"])
        #expect(rows.rows == ["Inbox", "Receipts/2026", "Sent"])
    }

    @Test func onlyTheFirstNineRowsAreNumbered() {
        let rows = numbered((1...12).map(String.init))
        #expect(rows.rows.count == 9)
        #expect(rows[.goTo(9)] == "9")
    }

    @Test func aNumberBeyondTheRowsNamesNone() {
        let rows = numbered(["Inbox"])
        #expect(rows[.goTo(2)] == nil)
        #expect(numbered([])[.goTo(1)] == nil)
    }

    @Test func eachCommandNamesItsOwnNumber() {
        let goTo = MailCommand.allCases.compactMap(\.rowShortcut).filter { if case .goTo = $0 { true } else { false } }
        #expect(goTo == (1...9).map(RowShortcut.goTo))
        let moveTo = MailCommand.allCases.compactMap(\.rowShortcut).filter {
            if case .moveTo = $0 { true } else { false }
        }
        #expect(moveTo == (1...9).map(RowShortcut.moveTo))
    }

    @Test func goToTakesCommandAndTheDigitAndMoveToAddsControl() {
        for number in 1...9 {
            let digit = Character(String(number))
            let goTo = MailCommand.allCases.first { $0.rowShortcut == .goTo(number) }
            let moveTo = MailCommand.allCases.first { $0.rowShortcut == .moveTo(number) }
            #expect(goTo?.keys.chord == KeyChord(.command, digit))
            #expect(moveTo?.keys.chord == KeyChord([.command, .control], digit))
        }
    }

    @Test func theNumberRowsLeaveActualSizeItsKeys() {
        #expect(MailCommand.actualSize.keys.chord == KeyChord(.command, "0"))
        #expect(MailCommand.allCases.compactMap(\.rowShortcut).allSatisfy { (1...9).contains($0.number) })
    }

    @Test func filterKeysAreMailsAndLeaveStarItsOwn() {
        #expect(MailCommand.toggleFilter.keys.chord == KeyChord(.command, "l"))
        #expect(MailCommand.star.keys.chord == KeyChord([.command, .shift], "l"))
        #expect(MailCommand.allCases.compactMap(\.filterOption) == ListFilter.Option.allCases)
    }

    @Test func theSubmenusHoldTheirCommands() {
        for command in MailCommand.allCases {
            switch command.place.submenu {
            case .goTo: #expect(command.rowShortcut.map { if case .goTo = $0 { true } else { false } } == true)
            case .moveTo: #expect(command.rowShortcut.map { if case .moveTo = $0 { true } else { false } } == true)
            case .filterBy: #expect(command.filterOption != nil)
            case nil: break
            }
        }
    }
}
