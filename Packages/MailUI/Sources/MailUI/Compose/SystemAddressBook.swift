import Contacts
import MailCore

/// The device's Contacts, through `CNContactStore`.
nonisolated public struct SystemAddressBook: DeviceContacts {
    public init() {}

    public var access: ContactsAccess {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .limited: .limited
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> ContactsAccess {
        // The status the user left is the answer, so the call's own result is not needed.
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        return access
    }

    @concurrent
    public func people() async throws -> [Contact] {
        let request = CNContactFetchRequest(keysToFetch: [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactEmailAddressesKey as CNKeyDescriptor,
        ])
        var people: [Contact] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName)
            people += contact.emailAddresses.map { Contact(name: name, address: $0.value as String) }
        }
        return people
    }
}
