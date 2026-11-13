import Foundation
import Testing

@testable import ICloudProvider

struct IMAPParsingTests {
    private func response(_ text: String) throws -> IMAPResponse {
        try IMAPParser.response(from: Data(text.utf8))
    }

    @Test func framerWaitsForALiteralsBytesAndTheLineAfterIt() {
        var framer = IMAPFramer()
        framer.append(Data("* 1 FETCH (BODY[] {5}\r\nab".utf8))
        #expect(framer.next() == nil)
        framer.append(Data("\r\nc)\r\n* 2 EXISTS\r\nA1 OK".utf8))
        #expect(framer.next() == Data("* 1 FETCH (BODY[] {5}\r\nab\r\nc)\r\n".utf8))
        #expect(framer.next() == Data("* 2 EXISTS\r\n".utf8))
        #expect(framer.next() == nil, "a line without its line break isn't whole yet")
    }

    @Test func taggedCompletionsCarryTheirCodeAndText() throws {
        #expect(
            try response("A3 NO [AUTHENTICATIONFAILED] Invalid credentials\r\n")
                == .completion(
                    tag: "A3",
                    IMAPStatus(condition: .no, code: [.atom("AUTHENTICATIONFAILED")], text: "Invalid credentials")))
    }

    @Test func untaggedStatusesAreToldApartFromData() throws {
        #expect(
            try response("* OK [UIDVALIDITY 3857529045] UIDs valid\r\n")
                == .status(
                    IMAPStatus(condition: .ok, code: [.atom("UIDVALIDITY"), .atom("3857529045")], text: "UIDs valid")))
        #expect(try response("* 172 EXISTS\r\n") == .data([.atom("172"), .atom("EXISTS")]))
        #expect(try response("+ go ahead\r\n") == .continuation)
    }

    @Test func fetchValuesKeepSectionsQuotesLiteralsAndNIL() throws {
        let text =
            #"* 12 FETCH (UID 7 FLAGS (\Seen) BODY[HEADER.FIELDS (REFERENCES)] {8}"# + "\r\n" + "abc\r\ndef"
            + #" X "a \"q\" \\" Y NIL)"# + "\r\n"
        let parsed = try response(text)
        #expect(
            parsed
                == .data([
                    .atom("12"), .atom("FETCH"),
                    .list([
                        .atom("UID"), .atom("7"), .atom("FLAGS"), .list([.atom(#"\Seen"#)]),
                        .atom("BODY[HEADER.FIELDS (REFERENCES)]"), .string(Data("abc\r\ndef".utf8)),
                        .atom("X"), .string(Data(#"a "q" \"#.utf8)), .atom("Y"), .nil,
                    ]),
                ]))
        guard case .data(let values) = parsed, let fetch = IMAPFetch(response: values) else {
            Issue.record("not a fetch: \(parsed)")
            return
        }
        #expect(fetch.items["UID"]?.number == 7)
        #expect(fetch.item(prefixed: "BODY[HEADER.FIELDS") == .string(Data("abc\r\ndef".utf8)))
        #expect(fetch.items["Y"] == .nil)
    }

    @Test func listResponsesNameTheMailboxAndItsRole() throws {
        func mailbox(_ line: String) throws -> IMAPMailbox? {
            guard case .data(let values) = try response(line + "\r\n") else { return nil }
            return IMAPMailbox(listResponse: values)
        }
        let sent = try #require(try mailbox(#"* LIST (\HasNoChildren \Sent) "/" "Sent Messages""#))
        #expect(sent.wireName == "Sent Messages")
        #expect(sent.role == .sent)
        #expect(sent.isSelectable)
        #expect(try mailbox(#"* LIST (\HasNoChildren) "/" INBOX"#)?.role == .inbox)
        let hebrew = try #require(try mailbox(#"* LIST (\Noselect) "/" "&BdAF0QXS-""#))
        #expect(hebrew.name == "אבג")
        #expect(hebrew.wireName == "&BdAF0QXS-", "commands keep the encoded name")
        #expect(!hebrew.isSelectable)
    }

    @Test func modifiedUTF7DecodesRFCExamples() {
        #expect(ModifiedUTF7.decode("~peter/mail/&U,BTFw-/&ZeVnLIqe-") == "~peter/mail/台北/日本語")
        #expect(ModifiedUTF7.decode("Tom &- Jerry") == "Tom & Jerry")
        #expect(ModifiedUTF7.decode("Archive") == "Archive")
    }

    @Test func aSnippetComesFromTheStartOfTheText() throws {
        let fields = "Content-Type: multipart/alternative; boundary=b\r\nContent-Transfer-Encoding: 7bit\r\n\r\n"
        let text =
            "--b\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nSee   you\r\nat =\r\nnoon caf=C3=A9 and mo"
        let line =
            #"* 1 FETCH (UID 4 FLAGS () INTERNALDATE "1-Nov-2026 09:00:00 +0000" ENVELOPE (NIL "Hi" NIL NIL NIL NIL NIL NIL NIL "<a@x>") "#
            + "BODY[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] {\(fields.utf8.count)}\r\n\(fields) "
            + "BODY[TEXT]<0> {\(text.utf8.count)}\r\n\(text))\r\n"
        guard case .data(let values) = try IMAPParser.response(from: Data(line.utf8)) else {
            Issue.record("not data")
            return
        }
        let header = try #require(IMAPFetch(response: values).flatMap(IMAPMessageHeader.init(fetch:)))
        #expect(header.snippet == "See you at noon café and mo")
        #expect(header.messageID == "a@x")
    }
}
