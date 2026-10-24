import MailCore
import Testing
import UIKit

@testable import MailUI

@MainActor
struct ThreadRowTests {
    private func configuration(preview: Int) -> ThreadRowConfiguration {
        ThreadRowConfiguration(
            thread: ThreadSummary(
                id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t"),
                subject: "Lunch", snippet: "Sure — let's do 12:30 at the usual place.",
                sender: Contact(name: "Dana Levi", address: "dana@example.com"),
                date: .now, isUnread: true, messageCount: 1, labelIDs: ["INBOX"]
            ),
            dateText: "9:41",
            accountColor: .systemTeal,
            previewLines: preview
        )
    }

    private func row(preview: Int) -> ThreadRowContentView {
        ThreadRowContentView(configuration: configuration(preview: preview))
    }

    @Test func listCellSelfSizes() {
        let cell = UICollectionViewListCell(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        cell.contentConfiguration = configuration(preview: 2)
        let size = cell.systemLayoutSizeFitting(
            CGSize(width: 402, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(size.height > 50 && size.height < 200, "\(size)")
    }

    @Test(arguments: [0, 2, 5])
    func rowHasAFiniteSelfSizingHeight(previewLines: Int) {
        let size = row(preview: previewLines).systemLayoutSizeFitting(
            CGSize(width: 402, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(size.height > 50 && size.height < 200, "\(size)")
    }
}

struct TextDirectionTests {
    @Test func firstStrongCharacterDecides() {
        #expect(TextDirection.of("Hello") == .leftToRight)
        #expect(TextDirection.of("שלום, מצורף הסיכום.") == .rightToLeft)
        #expect(TextDirection.of("12:30 — פגישה") == .rightToLeft, "digits and punctuation are not strong")
        #expect(TextDirection.of("Re: סיכום פגישה") == .leftToRight)
        #expect(TextDirection.of("مرحبا") == .rightToLeft)
        #expect(TextDirection.of("12:30!") == nil)
        #expect(TextDirection.of("") == nil)
    }

    @Test func subjectsAreDecidedPastReplyPrefixes() {
        #expect(TextDirection.of(subject: "Re: סיכום פגישה") == .rightToLeft)
        #expect(TextDirection.of(subject: "RE[2]: Fwd: סיכום") == .rightToLeft)
        #expect(TextDirection.of(subject: "השב: Quarterly report") == .leftToRight)
        #expect(TextDirection.of(subject: "Review → Thursday?") == .leftToRight, "a word that starts like a prefix")
        #expect(TextDirection.of(subject: "Re: 12:30") == .leftToRight, "only the prefix has letters")
    }

    @Test @MainActor func hebrewContentGetsARightToLeftParagraphInAnEnglishInterface() throws {
        let label = UILabel()
        label.setContentText("שלום עולם.")
        let style = try #require(
            label.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        #expect(style.baseWritingDirection == .rightToLeft)
        #expect(style.alignment == .right)
    }
}
