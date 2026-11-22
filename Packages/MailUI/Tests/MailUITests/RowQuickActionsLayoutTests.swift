import MailCore
import Testing
import UIKit

@testable import MailUI

/// Where a hovered row puts its quick actions: in the time's place in its upper trailing corner, clear of the sender,
/// the subject and the preview, on either side in either direction.
@MainActor
struct RowQuickActionsLayoutTests {
    private let subjectText = "Quarterly planning notes and the follow-ups from Tuesday's long review meeting"
    private let senderText = "Dana Levi-Montalcini of the Planning and Operations Department"
    private let previewText = "Here is everything we agreed on, and the owners for each item."

    private func row(width: CGFloat, direction: UISemanticContentAttribute) -> (ThreadRowContentView, HoverActionsView)
    {
        let row = ThreadRowContentView(
            configuration: ThreadRowConfiguration(
                thread: ThreadSummary(
                    id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t"), subject: subjectText,
                    snippet: previewText,
                    sender: Contact(name: senderText, address: "dana@example.com"), date: .now, isUnread: true,
                    messageCount: 1, labelIDs: ["INBOX"]),
                dateText: "9:41 AM", account: .implied(.teal)))
        // An app in Hebrew lays every view out right to left.
        force(direction, on: row)
        let height = row.systemLayoutSizeFitting(
            CGSize(width: width, height: 0), withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        row.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let capsule = HoverActionsView(
            actions: HoverActions.standard.shown.map {
                HoverAction(face: HoverAction.Face(title: "\($0)", symbol: "star", choice: $0), run: {})
            })
        row.quickActions = capsule
        force(direction, on: capsule)
        row.layoutIfNeeded()
        return (row, capsule)
    }

    private func fittingHeight(of row: ThreadRowContentView) -> CGFloat {
        row.systemLayoutSizeFitting(
            CGSize(width: row.bounds.width, height: 0), withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func force(_ direction: UISemanticContentAttribute, on view: UIView) {
        view.semanticContentAttribute = direction
        for subview in view.subviews { force(direction, on: subview) }
    }

    private func label(showing text: String, in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.attributedText?.string == text || label.text == text { return label }
        return view.subviews.lazy.compactMap { label(showing: text, in: $0) }.first
    }

    @Test(arguments: [
        (CGFloat(300), UISemanticContentAttribute.forceLeftToRight), (300, .forceRightToLeft),
        (900, .forceLeftToRight), (900, .forceRightToLeft),
    ])
    func theActionsSitInTheUpperTrailingCornerClearOfTheText(width: CGFloat, direction: UISemanticContentAttribute)
        throws
    {
        let (row, capsule) = row(width: width, direction: direction)
        let frame = capsule.convert(capsule.bounds, to: row)
        let subject = try #require(label(showing: subjectText, in: row))
        let sender = try #require(label(showing: senderText, in: row))
        let inset = ThreadRowMetrics.insets.trailing
        if direction == .forceRightToLeft {
            #expect(abs(frame.minX - inset) < 0.5, "at the left edge's margin")
        } else {
            #expect(abs(row.bounds.maxX - frame.maxX - inset) < 0.5, "at the right edge's margin")
        }
        #expect(frame.midY < row.bounds.midY, "in the upper half")
        #expect(frame.maxY <= subject.convert(subject.bounds, to: row).minY + 0.5, "above the subject")
        #expect(!frame.intersects(sender.convert(sender.bounds, to: row)), "the sender ends before them")
    }

    /// The capsule floats over the corner: showing it, hiding it and laying the row out again move no text, and the
    /// row asks for the same height, so the list never shifts under the pointer or on a click.
    @Test(arguments: [
        (CGFloat(300), UISemanticContentAttribute.forceLeftToRight), (300, .forceRightToLeft),
        (900, .forceLeftToRight), (900, .forceRightToLeft),
    ])
    func theActionsChangeNeitherTheRowsHeightNorWhereItsTextSits(
        width: CGFloat, direction: UISemanticContentAttribute
    ) throws {
        let (row, capsule) = row(width: width, direction: direction)
        let subject = try #require(label(showing: subjectText, in: row))
        let sender = try #require(label(showing: senderText, in: row))
        let preview = try #require(label(showing: previewText, in: row))
        func textFrames() -> [CGRect] { [subject, sender, preview].map { $0.convert($0.bounds, to: row) } }
        row.quickActions = nil
        row.layoutIfNeeded()
        let height = fittingHeight(of: row)
        let frames = textFrames()

        row.quickActions = capsule
        row.layoutIfNeeded()
        #expect(fittingHeight(of: row) == height, "showing them")
        #expect(textFrames().map(\.minY) == frames.map(\.minY), "showing them")
        #expect(textFrames()[0] == frames[0], "the subject stays put")

        // A click selects the row and lays the list out again, with the pointer still over it.
        row.frame.size.height = fittingHeight(of: row)
        row.setNeedsLayout()
        row.layoutIfNeeded()
        #expect(row.bounds.height == height, "laid out again")
        #expect(textFrames().map(\.minY) == frames.map(\.minY), "laid out again")

        row.quickActions = nil
        row.layoutIfNeeded()
        #expect(fittingHeight(of: row) == height, "hiding them")
        #expect(textFrames().map(\.minY) == frames.map(\.minY), "hiding them")
    }
}
