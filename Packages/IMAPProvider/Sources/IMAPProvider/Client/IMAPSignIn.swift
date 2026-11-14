import Foundation
import MailCore

/// Signing in to a mail account on any IMAP and SMTP server with a user name and password. Both servers are logged
/// in to first, so an account is only added once it can read and send; then the settings and password are kept
/// together in the `SecretStore`, as one item for the account.
public struct IMAPSignIn: Sendable {
    /// Which of the account's servers a failure is about.
    public enum Server: Sendable, Equatable {
        case imap, smtp
    }

    public enum Failure: Error, Equatable {
        /// The server refused the user name or the password.
        case refused(Server)
        /// The server won't turn on TLS, so the password wasn't sent.
        case insecure(Server)
        /// The server couldn't be reached or didn't answer as IMAP or SMTP does: most often a wrong host name or
        /// port, or a port that wants the other security.
        case unreachable(Server)
        /// The account has no stored login, as after the Keychain was reset.
        case signedOut
    }

    private let secrets: any SecretStore
    private let connect: @Sendable (MailServer) async throws -> any MailTransport

    #if canImport(Network)
        public init(secrets: any SecretStore) {
            self.init(secrets: secrets) { StreamTransport(to: $0) }
        }
    #endif

    init(secrets: any SecretStore, connect: @escaping @Sendable (MailServer) async throws -> any MailTransport) {
        self.secrets = secrets
        self.connect = connect
    }

    /// Logs in to both servers, then keeps `settings` and `password` for `accountID`.
    public func signIn(settings: MailServerSettings, password: String, accountID: AccountID) async throws {
        let credentials = IMAPCredentials(user: settings.username, password: password)
        try await checking(.imap) {
            let connection = try await IMAPConnection(
                transport: try await connect(settings.imap), security: settings.imap.security)
            do {
                if await connection.state == .notAuthenticated {
                    try await connection.login(user: credentials.user, password: credentials.password)
                }
            } catch {
                await connection.close()
                throw error
            }
            try? await connection.logout()
        }
        try await checking(.smtp) {
            try await SMTPClient(credentials: credentials, security: settings.smtp.security) {
                try await connect(settings.smtp)
            }.verify()
        }
        let login = IMAPLogin(settings: settings, password: password)
        try secrets.set(try JSONEncoder().encode(login), for: Self.key(accountID))
    }

    /// The stored settings and password. Throws `Failure.signedOut` when there are none.
    public func login(for accountID: AccountID) throws -> IMAPLogin {
        guard let data = try secrets.data(for: Self.key(accountID)),
            let login = try? JSONDecoder().decode(IMAPLogin.self, from: data)
        else { throw Failure.signedOut }
        return login
    }

    /// Forgets the login on this device. Nothing changes at the server.
    public func signOut(_ accountID: AccountID) throws {
        try secrets.remove(Self.key(accountID))
    }

    /// Runs `check` against `server`, naming the server in whatever went wrong. Cancellation stays cancellation.
    private func checking(_ server: Server, _ check: () async throws -> Void) async throws {
        do {
            try await check()
        } catch IMAPError.authenticationFailed, SMTPError.authenticationFailed {
            throw Failure.refused(server)
        } catch IMAPError.insecure, SMTPError.insecure {
            throw Failure.insecure(server)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.unreachable(server)
        }
    }

    private static func key(_ accountID: AccountID) -> String { "imap.\(accountID.rawValue).login" }
}

/// What an account logs in with: its servers and its password.
public struct IMAPLogin: Codable, Hashable, Sendable {
    public var settings: MailServerSettings
    public var password: String

    public init(settings: MailServerSettings, password: String) {
        self.settings = settings
        self.password = password
    }
}
