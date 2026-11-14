import Foundation
import MailCore
import Testing

@testable import IMAPProvider

struct IMAPSignInTests {
    private let account = AccountID(rawValue: "other")
    private let settings = MailServerSettings(
        imap: MailServer(host: "imap.example.com", port: 993, security: .tls),
        smtp: MailServer(host: "smtp.example.com", port: 465, security: .tls),
        username: "dana@example.com")

    private static let imapLogin = """
        S: * OK ready
        C: A1 LOGIN "dana@example.com" "secret"
        S: A1 OK done
        C: A2 LOGOUT
        S: * BYE
        S: A2 OK
        """

    private static let smtpLogin = """
        S: 220 smtp.example.com ESMTP
        C: EHLO goodmail.app
        S: 250-smtp.example.com
        S: 250 AUTH PLAIN
        C: AUTH PLAIN AGRhbmFAZXhhbXBsZS5jb20Ac2VjcmV0
        S: 235 OK
        C: QUIT
        S: 221 Bye
        """

    private func signIn(imap: String, smtp: String, secrets: SignInTests.MemorySecrets) -> IMAPSignIn {
        let imapTransport = ScriptedTransport(transcript: imap)
        let smtpTransport = ScriptedTransport(transcript: smtp)
        return IMAPSignIn(secrets: secrets) { server in
            server.host.hasPrefix("imap") ? imapTransport : smtpTransport
        }
    }

    @Test func bothServersAreLoggedInToBeforeTheLoginIsKept() async throws {
        let secrets = SignInTests.MemorySecrets()
        let signIn = signIn(imap: Self.imapLogin, smtp: Self.smtpLogin, secrets: secrets)
        try await signIn.signIn(settings: settings, password: "secret", accountID: account)
        #expect(try signIn.login(for: account) == IMAPLogin(settings: settings, password: "secret"))
        try signIn.signOut(account)
        #expect(throws: IMAPSignIn.Failure.signedOut) { try signIn.login(for: account) }
    }

    @Test func aRefusalNamesTheServerAndNothingIsKept() async throws {
        let secrets = SignInTests.MemorySecrets()
        let imapRefused = signIn(
            imap: "S: * OK ready\nC: A1 LOGIN \"dana@example.com\" \"secret\"\nS: A1 NO Login failed.",
            smtp: Self.smtpLogin, secrets: secrets)
        await #expect(throws: IMAPSignIn.Failure.refused(.imap)) {
            try await imapRefused.signIn(settings: settings, password: "secret", accountID: account)
        }

        let smtpRefused = signIn(
            imap: Self.imapLogin,
            smtp: Self.smtpLogin.replacing("S: 235 OK", with: "S: 535 5.7.8 Bad credentials"), secrets: secrets)
        await #expect(throws: IMAPSignIn.Failure.refused(.smtp)) {
            try await smtpRefused.signIn(settings: settings, password: "secret", accountID: account)
        }
        #expect(throws: IMAPSignIn.Failure.signedOut) { try smtpRefused.login(for: account) }
    }

    @Test func aRefusedLoginClosesItsConnection() async throws {
        let transport = ScriptedTransport(
            transcript: "S: * OK ready\nC: A1 LOGIN \"dana@example.com\" \"secret\"\nS: A1 NO Login failed.")
        let signIn = IMAPSignIn(secrets: SignInTests.MemorySecrets()) { _ in transport }
        await #expect(throws: IMAPSignIn.Failure.refused(.imap)) {
            try await signIn.signIn(settings: settings, password: "secret", accountID: account)
        }
        #expect(await transport.isClosed)
    }

    @Test func aServerThatIsntIMAPIsUnreachable() async throws {
        let signIn = signIn(imap: "S: HTTP/1.1 400 Bad Request", smtp: "", secrets: SignInTests.MemorySecrets())
        await #expect(throws: IMAPSignIn.Failure.unreachable(.imap)) {
            try await signIn.signIn(settings: settings, password: "secret", accountID: account)
        }
    }
}
