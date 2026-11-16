import Foundation
import MailCore
import Testing

@testable import IMAPProvider

/// Snippets from the start of a message's text, which can be all style sheet, as Apple's TestFlight mail is.
struct SnippetTests {
    static let html =
        #"<html><head><title>Ready</title><style type="text/css">"#
        + String(repeating: "A { text-decoration: none; } A:link { color: #0088CC; } ", count: 60)
        + "</style></head><body><p>Goodmail 1.0 (18) for iOS is now available to test.</p></body></html>"
    /// The first bytes of `html`, as many as a header fetch asks for.
    static let cut = String(decoding: html.utf8.prefix(IMAPCommand.snippetBytes), as: UTF8.self)

    /// One message's line of a header FETCH, with an HTML body's start.
    static func fetchLine(uid: UInt32, text: String) -> String {
        let fields = "Content-Type: text/html; charset=utf-8\r\n\r\n"
        return
            #"S: * 1 FETCH (UID \#(uid) FLAGS () INTERNALDATE "16-Nov-2026 09:43:00 +0000" ENVELOPE (NIL "Ready" NIL NIL NIL NIL NIL NIL NIL "<m\#(uid)@apple.com>") "#
            + "BODY[HEADER.FIELDS (CONTENT-TYPE)] {\(fields.utf8.count)}\\r\\n\(fields.replacing("\r\n", with: "\\r\\n")) "
            + "BODY[TEXT]<0> {\(text.utf8.count)}\\r\\n\(text))"
    }

    static func header(uid: UInt32, text: String, fetchedTextBytes: Int) throws -> IMAPMessageHeader {
        let line = fetchLine(uid: uid, text: text).dropFirst(3).replacing("\\r\\n", with: "\r\n") + "\r\n"
        guard case .data(let values) = try IMAPParser.response(from: Data(line.utf8)) else {
            throw ScriptedTransport.Unexpected(description: "not data: \(line)")
        }
        return try #require(
            IMAPFetch(response: values).flatMap { IMAPMessageHeader(fetch: $0, fetchedTextBytes: fetchedTextBytes) })
    }

    @Test func textCutShortInsideTheStylesHasNoWordsYet() throws {
        #expect(Self.html.utf8.count > IMAPCommand.snippetBytes)
        let header = try Self.header(uid: 40, text: Self.cut, fetchedTextBytes: IMAPCommand.snippetBytes)
        #expect(header.snippet == .pastFetchedBytes)
    }

    @Test func wholeTextWithoutWordsHasAnEmptySnippet() throws {
        let header = try Self.header(uid: 40, text: "<p></p>", fetchedTextBytes: IMAPCommand.snippetBytes)
        #expect(header.snippet == .found(""))
    }

    @Test func textPastItsStylesGivesTheFirstWords() throws {
        let header = try Self.header(uid: 40, text: Self.html, fetchedTextBytes: IMAPCommand.longSnippetBytes)
        #expect(header.snippet == .found("Goodmail 1.0 (18) for iOS is now available to test."))
    }

    @Test func headersFetchMoreTextForMessagesWhoseStartHoldsNoWords() async throws {
        let transcript =
            """
            S: * OK ready
            C: A1 LOGIN "dana@icloud.com" "abcd-efgh-ijkl-mnop"
            S: A1 OK authenticated
            C: A2 SELECT "INBOX"
            S: * 2 EXISTS
            S: * OK [UIDVALIDITY 7] UIDs valid.
            S: A2 OK [READ-WRITE] SELECT completed
            C: A3 UID FETCH 40:41 \(IMAPCommand.headerItems(textBytes: IMAPCommand.snippetBytes))
            \(Self.fetchLine(uid: 40, text: Self.cut))
            \(Self.fetchLine(uid: 41, text: "<p>Lunch at noon?</p>"))
            S: A3 OK FETCH completed
            C: A4 UID FETCH 40 \(IMAPCommand.headerItems(textBytes: IMAPCommand.longSnippetBytes))
            \(Self.fetchLine(uid: 40, text: Self.html))
            S: A4 OK FETCH completed
            """
        let connection = try await IMAPConnection(
            transport: ScriptedTransport(transcript: transcript), security: .tls)
        try await connection.login(user: "dana@icloud.com", password: "abcd-efgh-ijkl-mnop")
        _ = try await connection.select("INBOX")

        let headers = try await connection.headers(of: [40, 41])

        #expect(headers.map(\.uid) == [40, 41])
        #expect(
            headers.map(\.snippet) == [
                .found("Goodmail 1.0 (18) for iOS is now available to test."), .found("Lunch at noon?"),
            ])
    }
}
