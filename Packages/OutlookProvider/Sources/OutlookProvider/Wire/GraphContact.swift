import Foundation
import MailCore

/// A saved contact, as `me/contacts` lists it.
struct GraphContact: Decodable {
    let displayName: String?
    let emailAddresses: [GraphMessage.Recipient.Address]?

    /// One per address. An address's own name, as in "Dana (work)", wins over the contact's.
    var contacts: [Contact] {
        (emailAddresses ?? []).compactMap { email in
            guard let address = email.address, !address.isEmpty else { return nil }
            return Contact(name: email.name ?? displayName, address: address)
        }
    }
}

/// Someone the account corresponds with, as `me/people` ranks them.
struct GraphPerson: Decodable {
    struct ScoredAddress: Decodable {
        let address: String?
    }

    let displayName: String?
    let scoredEmailAddresses: [ScoredAddress]?

    var contacts: [Contact] {
        (scoredEmailAddresses ?? []).compactMap { email in
            guard let address = email.address, !address.isEmpty else { return nil }
            return Contact(name: displayName, address: address)
        }
    }
}
