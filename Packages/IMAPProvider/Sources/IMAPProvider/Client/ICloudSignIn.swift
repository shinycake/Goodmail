import Foundation
public import MailCore

/// Signing in to iCloud Mail with an app-specific password: iCloud's IMAP doesn't take the Apple Account password,
/// and has no OAuth. The password is checked by logging in, then kept in the `SecretStore` for the account.
public struct ICloudSignIn: Sendable {
    public enum Failure: Error, Equatable {
        /// iCloud refused the address or the password.
        case wrongPassword
        /// The account has no stored password, as after the Keychain was reset.
        case signedOut
    }

    private let secrets: any SecretStore
    private let connect: @Sendable () async throws -> any MailTransport

    #if canImport(Network)
        public init(secrets: any SecretStore) {
            self.init(secrets: secrets) { StreamTransport(to: .icloudIMAP) }
        }
    #endif

    init(secrets: any SecretStore, connect: @escaping @Sendable () async throws -> any MailTransport) {
        self.secrets = secrets
        self.connect = connect
    }

    /// Logs in to check `appPassword`, then stores it for `accountID`. Spaces and dashes are as Apple shows the
    /// password (`abcd-efgh-ijkl-mnop`); spaces someone typed are dropped.
    public func signIn(email: String, appPassword: String, accountID: AccountID) async throws {
        let credentials = IMAPCredentials(
            user: email.trimmingCharacters(in: .whitespaces), password: appPassword.filter { $0 != " " })
        let connection = try await IMAPConnection(
            transport: try await connect(), security: MailServer.icloudIMAP.security)
        do {
            try await connection.login(user: credentials.user, password: credentials.password)
        } catch {
            await connection.close()
            if case IMAPError.authenticationFailed = error { throw Failure.wrongPassword }
            throw error
        }
        try? await connection.logout()
        try secrets.set(Data(credentials.password.utf8), for: Self.key(accountID))
    }

    /// The stored password. Throws `Failure.signedOut` when there is none.
    public func appPassword(for accountID: AccountID) throws -> String {
        guard let data = try secrets.data(for: Self.key(accountID)) else { throw Failure.signedOut }
        return String(decoding: data, as: UTF8.self)
    }

    /// Forgets the password on this device. The password stays valid at Apple until revoked there.
    public func signOut(_ accountID: AccountID) throws {
        try secrets.remove(Self.key(accountID))
    }

    /// Where the account's app-specific password is stored.
    public static func key(_ accountID: AccountID) -> String { "icloud.\(accountID.rawValue).appPassword" }
}
