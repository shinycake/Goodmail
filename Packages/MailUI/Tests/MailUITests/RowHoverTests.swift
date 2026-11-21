import MailCore
import Testing
import UIKit

@testable import MailUI

/// Finding the row the pointer rests on, to put the quick actions on.
@MainActor
struct RowHoverTests {
    private let configuration = ThreadRowConfiguration(
        thread: ThreadSummary(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t"), subject: "Lunch",
            snippet: "Sure", sender: Contact(name: "Dana Levi", address: "dana@example.com"), date: .now,
            isUnread: true, messageCount: 1, labelIDs: ["INBOX"]),
        dateText: "9:41", account: .implied(.teal))

    @Test func findsTheRowInACellSetUpAsTheListSetsItsRowsUp() {
        // A content configuration makes its view the cell's content view, so the row is that view, not one below it.
        let cell = UICollectionViewListCell(frame: CGRect(x: 0, y: 0, width: 402, height: 80))
        cell.contentConfiguration = configuration
        #expect(RowHover.row(in: cell) != nil)
    }

    @Test func aRowUnderThePointerTintsAndKeepsItsButtonsInsideIt() throws {
        let row = ThreadRowContentView(configuration: configuration)
        row.frame = CGRect(x: 0, y: 0, width: 402, height: 80)
        row.frame.size.height =
            row.systemLayoutSizeFitting(
                CGSize(width: 402, height: 0), withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        #expect(row.backgroundColor == nil)
        let buttons = HoverActionsView(actions: [
            HoverAction(face: HoverAction.Face(title: "Archive", symbol: "archivebox", choice: .archive), run: {})
        ])
        row.quickActions = buttons
        row.layoutIfNeeded()
        #expect(row.backgroundColor == .tertiarySystemFill)
        let frame = buttons.convert(buttons.bounds, to: row)
        #expect(row.bounds.insetBy(dx: 0, dy: 1).contains(frame), "the row's separators don't cut through them")
        row.quickActions = nil
        #expect(row.backgroundColor == nil)
    }

    @Test func aCellWithoutARowHasNone() {
        let cell = UICollectionViewListCell(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        var content = cell.defaultContentConfiguration()
        content.text = "Primary"
        cell.contentConfiguration = content
        #expect(RowHover.row(in: cell) == nil)
    }
}
