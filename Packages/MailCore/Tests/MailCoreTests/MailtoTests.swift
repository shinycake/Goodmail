import Foundation
import Testing

@testable import MailCore

struct MailtoTests {
    private let account = AccountID(rawValue: "A1")

    private func draft(_ string: String) -> Draft? {
        URL(string: string).flatMap { Draft(mailto: $0, from: account) }
    }

    @Test func recipientsSubjectAndBodyComeFromTheLink() throws {
        let draft = try #require(
            draft(
                "mailto:dana@example.com,yael@example.com?cc=ops@example.com&bcc=me@example.com&subject=Lunch%20today%3F&body=Hi%2C%0Afree%20at%201%3F"
            ))
        #expect(draft.accountID == account)
        #expect(draft.to.map(\.address) == ["dana@example.com", "yael@example.com"])
        #expect(draft.cc.map(\.address) == ["ops@example.com"])
        #expect(draft.bcc.map(\.address) == ["me@example.com"])
        #expect(draft.subject == "Lunch today?")
        #expect(draft.body.plain == "Hi,\nfree at 1?")
        #expect(draft.body.html == "<div dir=\"auto\">Hi,</div><div dir=\"auto\">free at 1?</div>")
    }

    @Test func aToFieldAddsToThePathAndHeadersAreCaseInsensitive() throws {
        let draft = try #require(draft("mailto:a@example.com?TO=b@example.com&Subject=Hi"))
        #expect(draft.to.map(\.address) == ["a@example.com", "b@example.com"])
        #expect(draft.subject == "Hi")
    }

    @Test func anEmptyLinkStartsAnEmptyMessage() throws {
        let draft = try #require(draft("mailto:"))
        #expect(draft.to.isEmpty)
        #expect(draft.subject.isEmpty)
    }

    @Test func encodedNamesAndHebrewSurvive() throws {
        let draft = try #require(
            draft("mailto:%22Dana%20Levi%22%20%3Cdana@example.com%3E?subject=%D7%A9%D7%9C%D7%95%D7%9D&body=%3Cb%3E"))
        #expect(draft.to == [Contact(name: "Dana Levi", address: "dana@example.com")])
        #expect(draft.subject == "שלום")
        #expect(draft.body.html == "<div dir=\"auto\">&lt;b&gt;</div>")
    }

    @Test func otherSchemesAreNotMailLinks() {
        #expect(draft("https://example.com") == nil)
    }
}
