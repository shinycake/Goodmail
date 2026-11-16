public import Foundation

/// What the two devices say to each other during a transfer, in order: the receiver's `hello`, then the sender's
/// `accounts` once the reader approved, or `declined`.
public enum TransferMessage: Codable, Equatable, Sendable {
    /// The receiver's key agreement public key, `proof` that it scanned the code (`TransferCipher.proof`), and the
    /// name the sender asks the reader to approve.
    case hello(key: Data, proof: Data, device: String)
    /// The accounts, sealed with the key both devices agreed on.
    case accounts(sealed: Data)
    /// The reader turned the transfer down on the sending device.
    case declined
}

/// The accounts a transfer carries, each with what it needs to sign in.
public struct TransferPayload: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let id: AccountID
        public let profile: SharedAccount.Profile
        /// The stored sign-in, as the account's `SecretStore` key holds it.
        public let signIn: Data

        public init(id: AccountID, profile: SharedAccount.Profile, signIn: Data) {
            self.id = id
            self.profile = profile
            self.signIn = signIn
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }
}

extension TransferPayload {
    /// The entries for accounts not on a device that has `accounts` already, by ID or by address at the same
    /// service, in the order they came.
    public func entries(newTo accounts: [Account]) -> [Entry] {
        entries.filter { entry in
            !accounts.contains { account in
                account.id == entry.id
                    || (account.service == entry.profile.service
                        && account.email.caseInsensitiveCompare(entry.profile.email) == .orderedSame)
            }
        }
    }
}
