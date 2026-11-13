import Foundation
import MailCore
import Testing

@testable import ICloudProvider

struct SignInTests {
    final class MemorySecrets: SecretStore, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: Data] = [:]

        func data(for key: String) throws -> Data? { lock.withLock { items[key] } }
        func set(_ data: Data, for key: String) throws { lock.withLock { items[key] = data } }
        func remove(_ key: String) throws { _ = lock.withLock { items.removeValue(forKey: key) } }
    }

    private let account = AccountID(rawValue: "icloud")

    private func signIn(_ transcript: String, secrets: MemorySecrets) -> ICloudSignIn {
        let transport = ScriptedTransport(transcript: transcript)
        return ICloudSignIn(secrets: secrets) { transport }
    }

    @Test func aPasswordThatLogsInIsKeptUntilSignOut() async throws {
        let secrets = MemorySecrets()
        let signIn = signIn(
            """
            S: * OK ready
            C: A1 LOGIN "dana@icloud.com" "abcd-efgh-ijkl-mnop"
            S: A1 OK done
            C: A2 LOGOUT
            S: * BYE
            S: A2 OK
            """, secrets: secrets)
        try await signIn.signIn(email: " dana@icloud.com", appPassword: "abcd-efgh-ijkl-mnop ", accountID: account)
        #expect(try signIn.appPassword(for: account) == "abcd-efgh-ijkl-mnop")
        try signIn.signOut(account)
        #expect(throws: ICloudSignIn.Failure.signedOut) { try signIn.appPassword(for: account) }
    }

    @Test func aRefusedPasswordIsNotKept() async throws {
        let secrets = MemorySecrets()
        let signIn = signIn(
            """
            S: * OK ready
            C: A1 LOGIN "dana@icloud.com" "my-apple-password"
            S: A1 NO [AUTHENTICATIONFAILED] Authentication failed
            """, secrets: secrets)
        await #expect(throws: ICloudSignIn.Failure.wrongPassword) {
            try await signIn.signIn(email: "dana@icloud.com", appPassword: "my-apple-password", accountID: account)
        }
        #expect(throws: ICloudSignIn.Failure.signedOut) { try signIn.appPassword(for: account) }
    }
}
