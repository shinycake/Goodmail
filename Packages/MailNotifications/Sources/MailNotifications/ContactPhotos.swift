import Contacts
public import Foundation

/// Photos the reader saved in Contacts, looked up by email address. Never asks for access: Contacts is only read
/// once the reader allowed it, as when they turned on recipient suggestions.
public enum ContactPhotos {
    /// The photo of the first contact with `address`, or `nil` without access, a match or a photo. Contacts reads
    /// block, so this runs off the main actor, as in the app's picture loads and the
    /// notification extension.
    public static func photo(for address: String) -> Data? {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: break
        case .notDetermined, .restricted, .denied: return nil
        @unknown default: return nil
        }
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: address)
        let keys = [CNContactThumbnailImageDataKey as any CNKeyDescriptor]
        let contacts = try? CNContactStore().unifiedContacts(matching: predicate, keysToFetch: keys)
        return contacts?.lazy.compactMap(\.thumbnailImageData).first
    }
}
