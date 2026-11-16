import Foundation

/// What the reader's devices know of one account through iCloud Keychain. Removing an account doesn't delete its
/// record but turns it into `removed`, so a device that hasn't heard yet can't mistake a missing record for one it
/// should share again.
public enum SharedAccount: Codable, Equatable, Sendable {
    case present(Profile)
    case removed

    /// Everything a device needs to add the account besides its sign-in, which is shared beside it.
    public struct Profile: Codable, Equatable, Sendable {
        public var email: String
        public var service: MailService
        public var name: String?
        /// `AccountColor.rawValue`.
        public var color: String
        /// The account's place in the order the reader put the accounts in.
        public var position: Int

        public init(_ account: Account, position: Int) {
            email = account.email
            service = account.service
            name = account.name
            color = account.color.rawValue
            self.position = position
        }

        /// The account as a device adds it. A color this build doesn't know reads as the first offered one.
        public func account(_ id: AccountID) -> Account {
            Account(
                id: id, email: email, color: AccountColor(rawValue: color) ?? AccountColor.presets[0],
                service: service, name: name)
        }
    }

    public var profile: Profile? {
        switch self {
        case .present(let profile): profile
        case .removed: nil
        }
    }
}
