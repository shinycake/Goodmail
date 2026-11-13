import Foundation
import MailCore

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
    private let connect: @Sendable () async throws -> any IMAPTransport

    #if canImport(Network)
        public init(secrets: any SecretStore) {
            self.init(secrets: secrets) { TLSTransport(host: ICloudClient.imapHost, port: 993) }
        }
    #endif

    init(secrets: any SecretStore, connect: @escaping @Sendable () async throws -> any IMAPTransport) {
        self.secrets = secrets
        self.connect = connect
    }

    /// Logs in to check `appPassword`, then stores it for `accountID`. Spaces and dashes are as Apple shows the
    /// password (`abcd-efgh-ijkl-mnop`); spaces someone typed are dropped.
    public func signIn(email: String, appPassword: String, accountID: AccountID) async throws {
        let credentials = ICloudCredentials(
            user: email.trimmingCharacters(in: .whitespaces), password: appPassword.filter { $0 != " " })
        let connection = try await IMAPConnection(transport: try await connect())
        do {
            try await connection.login(user: credentials.user, password: credentials.password)
        } catch IMAPError.authenticationFailed {
            throw Failure.wrongPassword
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

    private static func key(_ accountID: AccountID) -> String { "icloud.\(accountID.rawValue).appPassword" }
}
