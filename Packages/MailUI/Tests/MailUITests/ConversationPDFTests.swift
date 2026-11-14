import Foundation
import MailCore
import PDFKit
import Testing

@testable import MailUI

/// A conversation laid out for print or sharing comes back as pages that carry its words, in time.
@MainActor
struct ConversationPDFTests {
    private func message(_ number: Int, from name: String, body: String) -> Message {
        Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m\(number)"), threadID: "t",
            from: Contact(name: name, address: "\(name.lowercased())@example.com"),
            to: [Contact(name: nil, address: "me@example.com")], subject: "Plan",
            date: Date(timeIntervalSince1970: 1_800_000_000 + Double(number) * 60),
            body: MessageBody(html: "<html><body><p>\(body)</p></body></html>"))
    }

    @Test(.timeLimit(.minutes(1)))
    func aTwoMessageConversationPrintsItsWords() async throws {
        let data = try await ConversationPDF.data(
            for: [
                message(1, from: "Dana", body: "Thursday works for me."), message(2, from: "Yael", body: "בטח, נתראה."),
            ],
            subject: "Plan for Thursday", allowsRemoteContent: [], attachmentData: { _, _ in Data() })

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2, "each short message fills one page, with none left blank")
        let text = try #require(document.string)
        #expect(text.contains("Plan for Thursday"))
        #expect(text.contains("Thursday works for me."))
        #expect(text.contains("נתראה"))
    }

    @Test(.timeLimit(.minutes(1)))
    func aLongMessageRunsOnToMorePages() async throws {
        let paragraphs = (1...120).map { "Line \($0) of the agenda." }.joined(separator: "</p><p>")
        let data = try await ConversationPDF.data(
            for: [message(1, from: "Dana", body: paragraphs)], subject: "Agenda", allowsRemoteContent: [],
            attachmentData: { _, _ in Data() })

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 2)
        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        #expect(pages.allSatisfy { !$0.isEmpty }, "no page is left blank")
        #expect(pages.last?.contains("Line 120 of the agenda.") == true, "the end of the message reaches the last page")
    }
}
