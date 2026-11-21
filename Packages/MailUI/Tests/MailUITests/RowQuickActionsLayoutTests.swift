import MailCore
import Testing
import UIKit

@testable import MailUI

/// Where a hovered row puts its quick actions: centered on the row near its trailing edge, every button whole, and More
/// only when the row is too narrow for every action.
@MainActor
struct RowQuickActionsLayoutTests {
    private let choices: [SwipeChoice] = [.read, .star, .archive, .snooze, .trash, .spam]

    private func row(width: CGFloat, direction: UISemanticContentAttribute = .unspecified)
        -> (ThreadRowContentView, HoverActionsView)
    {
        let row = ThreadRowContentView(
            configuration: ThreadRowConfiguration(
                thread: ThreadSummary(
                    id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t"),
                    subject: "Quarterly planning notes and the follow-ups from Tuesday",
                    snippet: "Here is everything we agreed on, and the owners for each item.",
                    sender: Contact(name: "Dana Levi", address: "dana@example.com"), date: .now, isUnread: true,
                    messageCount: 1, labelIDs: ["INBOX"]),
                dateText: "9:41", account: .implied(.teal)))
        let height = row.systemLayoutSizeFitting(
            CGSize(width: width, height: 0), withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        row.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let capsule = HoverActionsView(
            actions: choices.map {
                HoverAction(face: HoverAction.Face(title: "\($0)", symbol: "star", choice: $0), run: {})
            })
        row.quickActions = capsule
        // An app in Hebrew lays every view out right to left.
        force(direction, on: row)
        row.layoutIfNeeded()
        return (row, capsule)
    }

    private func force(_ direction: UISemanticContentAttribute, on view: UIView) {
        view.semanticContentAttribute = direction
        for subview in view.subviews { force(direction, on: subview) }
    }

    @Test(arguments: [CGFloat(200), 490, 900])
    func noButtonIsClippedAtAnyWidth(_ width: CGFloat) {
        let (row, capsule) = row(width: width)
        let frame = capsule.convert(capsule.bounds, to: row)
        #expect(frame.width <= width * 0.6 + 0.5, "at most about 60% of the row")
        #expect(row.bounds.insetBy(dx: 0, dy: 1).contains(frame))
        #expect(abs(frame.midY - row.bounds.midY) < 0.5, "centered on the row, not its first line")
        #expect(abs(row.bounds.maxX - frame.maxX - ThreadRowMetrics.quickActionsInset) < 0.5)
        for button in capsule.shownButtons {
            #expect(button.frame.size == CGSize(width: 28, height: 28))
            #expect(capsule.bounds.contains(button.frame), "a button whole inside the capsule")
        }
    }

    @Test func moreShowsOnlyWhenTheRowIsTooNarrowForEveryAction() {
        #expect(row(width: 200).1.fit.overflows)
        #expect(row(width: 200).1.fit.shown < choices.count)
        #expect(!row(width: 490).1.fit.overflows)
        #expect(row(width: 490).1.shownButtons.count == choices.count)
        #expect(!row(width: 900).1.fit.overflows)
    }

    @Test func inRightToLeftTheActionsSitAtTheLeftEdge() {
        let (row, capsule) = row(width: 490, direction: .forceRightToLeft)
        let frame = capsule.convert(capsule.bounds, to: row)
        #expect(abs(frame.minX - ThreadRowMetrics.quickActionsInset) < 0.5)
        let first = capsule.shownButtons[0].frame
        #expect(first.maxX > capsule.bounds.midX, "the first action reads first, from the right")
    }

    @Test func theTextFadesUnderTheActionsAndComesBackAfter() throws {
        let (row, _) = row(width: 490)
        let text = try #require(row.subviews.first { $0.layer.mask != nil })
        #expect(text is UIStackView)
        row.quickActions = nil
        row.layoutIfNeeded()
        #expect(text.layer.mask == nil)
    }
}
