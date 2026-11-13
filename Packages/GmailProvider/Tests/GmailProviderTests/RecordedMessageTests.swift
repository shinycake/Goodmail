import Foundation
import MailCore
import Testing

@testable import GmailProvider

/// Reading the TestMail corpus as Gmail actually returned it (`scripts/record-fixtures`, ADR-010).
struct RecordedMessageTests {
    private let keychain = InMemorySecretStore()

    private func messages(_ thread: String) async throws -> (GmailClient, FixtureHTTPClient, [Message]) {
        let json = try Data(contentsOf: fixtureURL("Recorded/\(thread)"))
        let id = try #require((try JSONSerialization.jsonObject(with: json) as? [String: Any])?["id"] as? String)
        let http = FixtureHTTPClient([
            "/token": [.init(fixture: "token-exchange")],
            "/gmail/v1/users/me/threads/\(id)": [.init(fixture: "Recorded/\(thread)")],
        ])
        let session = try await OAuthSession.signIn(
            client: .gmail, code: "4/abc", pkce: .generate(), http: http, keychain: keychain)
        let gmail = GmailClient(session: session.session, http: http, retryDelays: [])
        return (gmail, http, try await gmail.messages(inThread: id))
    }

    @Test func windows1255MailReadsAsHebrewThoughGmailAlreadyConvertedIt() async throws {
        let message = try #require(try await messages("hebrew-windows-1255").2.first)
        #expect(message.subject == "סיכום פגישה – תקציב 2027")
        #expect(message.from == Contact(name: "אבי מזרחי", address: "avi@example.co.il"))
        let body = try #require(message.body.plain)
        #expect(body.hasPrefix("שלום,"))
        #expect(body.contains("סעיף 3 (תקציב 2027) עדיין פתוח"))
        #expect(body.contains("03-5551234"))
        #expect(message.body.html == nil)
    }

    @Test func iso88598iMailReadsAsHebrew() async throws {
        let message = try #require(try await messages("hebrew-iso-8859-8-i").2.first)
        #expect(message.body.plain?.hasPrefix("תזכורת: התור לרופא ביום רביעי בשעה 09:40.") == true)
    }

    @Test func gmailThreadIsOldestFirstWithPeopleAndReplyHeaders() async throws {
        let thread = try await messages("gmail-mixed-thread").2
        #expect(thread.map(\.internetMessageID) == ["gm-1@goodmail.test", "gm-2@goodmail.test", "gm-3@goodmail.test"])
        #expect(thread[2].references == ["gm-1@goodmail.test", "gm-2@goodmail.test"])
        #expect(thread[1].from.name == "יעל כהן")
        #expect(thread[1].to.map(\.address) == ["dana@example.com", "tester@example.com"])
        #expect(thread[1].body.html?.contains(#"<div dir="rtl">בטח, יום חמישי ב-14:00 מתאים."#) == true)
        #expect(thread[1].body.html?.contains(#"class="gmail_quote""#) == true)
        #expect(thread[1].body.plain?.hasPrefix("בטח") == true, "the plain alternative is kept as well")
        #expect(thread.allSatisfy { $0.isUnread })
        #expect(thread[0].subject == "Review → Thursday?")
    }

    @Test func inlineImageAndAttachmentAreSeparatedFromTheBody() async throws {
        let (gmail, _, thread) = try await messages("inline-image-and-pdf")
        let message = try #require(thread.first)
        #expect(message.body.html?.contains("cid:logo@goodmail.test") == true)

        let logo = try #require(message.attachments.first { $0.contentID == "logo@goodmail.test" })
        #expect(logo.isInline)
        #expect(logo.mimeType == "image/png")
        let pdf = try #require(message.attachments.first { $0.mimeType == "application/pdf" })
        #expect(pdf.filename == "הצעת מחיר.pdf")
        #expect(!pdf.isInline)
        #expect(pdf.fetchToken != nil)

        _ = gmail  // Attachment data is covered below, with its own routes.
    }

    @Test func attachmentDataDecodes() async throws {
        let (_, _, thread) = try await messages("inline-image-and-pdf")
        let message = try #require(thread.first)
        for (partID, signature) in [("0.1", Data([0x89, 0x50, 0x4E, 0x47])), ("1", Data("%PDF".utf8))] {
            let attachment = try #require(message.attachments.first { $0.id == partID })
            let http = FixtureHTTPClient([
                "/token": [.init(fixture: "token-exchange")],
                "/gmail/v1/users/me/messages/\(message.id.messageID)/attachments/\(attachment.fetchToken!)": [
                    .init(fixture: "Recorded/inline-image-and-pdf-part-\(partID)")
                ],
            ])
            let session = try await OAuthSession.signIn(
                client: .gmail, code: "4/abc", pkce: .generate(), http: http, keychain: keychain)
            let data = try await GmailClient(session: session.session, http: http).data(for: attachment, in: message.id)
            #expect(data.prefix(4) == signature)
            #expect(data.count == attachment.size)
        }
    }

    @Test func outlookAndAppleMailKeepTheirDirectionMarkup() async throws {
        let outlook = try #require(try await messages("outlook-hebrew-reply").2.first)
        #expect(outlook.body.html?.contains(#"dir="rtl""#) == true)
        #expect(outlook.body.html?.contains("divRplyFwdMsg") == true)
        let apple = try #require(try await messages("apple-mail-reply").2.first)
        #expect(apple.body.html?.contains(#"<blockquote type="cite">"#) == true)
    }

    @Test func plainTextQuotingSurvives() async throws {
        let message = try #require(try await messages("plain-quoted-mixed").2.first)
        #expect(message.body.plain?.contains(">> Can we ship v2.1 this week?") == true)
        #expect(message.to.count == 2)
    }
}
