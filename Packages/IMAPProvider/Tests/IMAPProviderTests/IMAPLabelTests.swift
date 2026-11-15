import Foundation
import MailCore
import Testing

@testable import IMAPProvider

/// The login transcript's folders: one user folder, עבודה (`&BeIF0QXVBdMF1A-`), beside the role folders.
struct IMAPLabelTests {
    private static let work = "&BeIF0QXVBdMF1A-"

    @Test func modifiedUTF7EncodesRFCExamplesAndRoundTrips() {
        #expect(ModifiedUTF7.encode("~peter/mail/台北/日本語") == "~peter/mail/&U,BTFw-/&ZeVnLIqe-")
        #expect(ModifiedUTF7.encode("Tom & Jerry") == "Tom &- Jerry")
        #expect(ModifiedUTF7.encode("עבודה") == Self.work)
        for name in ["Archive", "קבלות 2026", "Mixed עברית & English", "😀 emoji", ""] {
            #expect(ModifiedUTF7.decode(ModifiedUTF7.encode(name)) == name)
        }
    }

    @Test func aNewFolderIsCreatedByItsEncodedName() async throws {
        let (client, transport) = Self.client(
            Self.loginThen(#"C: A4 CREATE "Projects/&BdcF0wXp-""#, "S: A4 OK CREATE completed"))

        let label = try await client.createLabel(named: "Projects/חדש")

        #expect(await transport.sent.last == "A4 CREATE \"Projects/&BdcF0wXp-\"\r\n")
        #expect(label == MailLabel(id: "Projects/&BdcF0wXp-", name: "Projects/חדש", kind: .user))
    }

    @Test func aNameTheServerRefusesIsRejected() async throws {
        let client = IMAPClientTests.client(
            Self.loginThen(#"C: A4 CREATE "Archive""#, "S: A4 NO [ALREADYEXISTS] Mailbox exists"),
            index: MemoryIndex())
        await #expect(throws: ProviderError.rejected) { try await client.createLabel(named: "Archive") }
    }

    @Test(arguments: ["", "  ", "Line\nbreak"])
    func aBlankNameOrOneWithALineBreakIsRejectedUnsent(_ name: String) async throws {
        let client = IMAPClientTests.client("", index: MemoryIndex())
        await #expect(throws: ProviderError.rejected) { try await client.createLabel(named: name) }
    }

    @Test func aUserFolderIsRenamed() async throws {
        let (client, transport) = Self.client(
            IMAPClientTests.login + "\n" + #"C: A5 RENAME "\#(Self.work)" "Work""# + "\nS: A5 OK RENAME completed")
        try await client.renameLabel(Self.work, to: "Work")
        #expect(await transport.sent.last == "A5 RENAME \"\(Self.work)\" \"Work\"\r\n")
    }

    @Test func aRoleFolderOrOneThatIsGoneIsNotRenamed() async throws {
        for id in ["Archive", "Gone"] {
            let client = IMAPClientTests.client(IMAPClientTests.login, index: MemoryIndex())
            await #expect(throws: ProviderError.notFound) { try await client.renameLabel(id, to: "Other") }
        }
    }

    @Test func aUserFolderIsDeletedAndOneThatIsGoneIsLeftAlone() async throws {
        let (deleting, sent) = Self.client(
            IMAPClientTests.login + "\n" + #"C: A5 DELETE "\#(Self.work)""# + "\nS: A5 OK DELETE completed")
        try await deleting.deleteLabel(Self.work)
        #expect(await sent.sent.last == "A5 DELETE \"\(Self.work)\"\r\n")

        let (gone, unsent) = Self.client(IMAPClientTests.login)
        try await gone.deleteLabel("Gone")
        #expect(await unsent.sent.last == "A4 LIST \"\" \"*\"\r\n")
    }

    @Test func deletingAFolderDeletesTheFoldersUnderItFirstButNotARoleFolder() async throws {
        let (client, transport) = Self.client(
            Self.loginThen(
                #"C: A4 LIST "" "*""#,
                #"S: * LIST (\HasNoChildren) "/" "INBOX""#,
                #"S: * LIST (\HasChildren) "/" "Work""#,
                #"S: * LIST (\Noselect \HasChildren) "/" "Work/2026""#,
                #"S: * LIST (\HasNoChildren) "/" "Work/2026/Q1""#,
                #"S: * LIST (\HasNoChildren) "/" "Work/Clients""#,
                #"S: * LIST (\HasNoChildren \Sent) "/" "Work/Sent""#,
                #"S: * LIST (\HasNoChildren) "/" "Workshop""#,
                "S: A4 OK LIST completed",
                #"C: A5 DELETE "Work/Clients""#, "S: A5 OK DELETE completed",
                #"C: A6 DELETE "Work/2026/Q1""#, "S: A6 OK DELETE completed",
                #"C: A7 DELETE "Work/2026""#, "S: A7 OK DELETE completed",
                #"C: A8 DELETE "Work""#, "S: A8 OK DELETE completed"))

        try await client.deleteLabel("Work")

        #expect(
            await transport.sent.filter { $0.contains(" DELETE ") } == [
                "A5 DELETE \"Work/Clients\"\r\n", "A6 DELETE \"Work/2026/Q1\"\r\n", "A7 DELETE \"Work/2026\"\r\n",
                "A8 DELETE \"Work\"\r\n",
            ],
            "each folder before the one holding it; not Sent, nor one whose name only starts the same")
    }

    /// A client that replays `transcript`, and its transport, to check what was sent.
    private static func client(_ transcript: String) -> (IMAPClient, ScriptedTransport) {
        let transport = ScriptedTransport(transcript: transcript)
        let credentials = IMAPClientTests.credentials
        let client = IMAPClient(
            accountID: IMAPClientTests.account,
            session: IMAPSession(credentials: credentials, security: .tls) { transport },
            smtp: SMTPClient(credentials: credentials, security: .startTLS) { ScriptedTransport(transcript: "") },
            index: MemoryIndex())
        return (client, transport)
    }

    /// Logging in, then `lines` in place of the folder list.
    private static func loginThen(_ lines: String...) -> String {
        (IMAPClientTests.login.components(separatedBy: "\n").prefix(8) + lines).joined(separator: "\n")
    }
}
