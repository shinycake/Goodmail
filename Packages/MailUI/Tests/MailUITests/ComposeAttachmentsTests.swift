import MailCore
import Testing
import UIKit

@testable import MailUI

@MainActor
struct ComposeAttachmentsTests {
    /// The file's capsule in a composer that opens with it, as a forward or a share does.
    private func chip(named filename: String) throws -> UIView {
        let file = DraftAttachment(filename: filename, mimeType: "application/pdf", data: Data(count: 193))
        let composer = ComposeViewController(
            viewModel: ComposeViewModel(
                draft: Draft(accountID: AccountID(rawValue: "a"), attachments: [file]),
                accountEmail: "me@example.com", send: { _, _ in }))
        let host = ComposeWindowController(composer: composer, placement: .sheet) {}
        host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        host.view.layoutIfNeeded()
        let files = try #require(composer.view.descendants(ComposeAttachmentsView.self).first)
        return try #require(files.arrangedSubviews.first)
    }

    @Test func aFileTheMessageOpensWithKeepsItsNameAndSizeOnALineEach() throws {
        let chip = try chip(named: "הצעת מחיר.pdf")
        #expect(chip.frame.width > 120)
        #expect(chip.frame.height < 70)
    }

    @Test func aLongNameStopsAtTheFieldsWidth() throws {
        let chip = try chip(named: String(repeating: "quarterly-report-", count: 12) + "final.pdf")
        let fields = try #require(chip.superview)
        #expect(chip.frame.width == fields.bounds.width)
        #expect(chip.frame.height < 70)
    }
}

extension UIView {
    fileprivate func descendants<View: UIView>(_ type: View.Type) -> [View] {
        subviews.flatMap { ($0 as? View).map { [$0] } ?? [] + $0.descendants(type) }
    }
}
