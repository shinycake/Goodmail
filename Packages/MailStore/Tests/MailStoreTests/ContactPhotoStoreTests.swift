import Foundation
import MailCore
import Testing

@testable import MailStore

/// The profile photos address books keep, which senders' pictures come from.
struct ContactPhotoStoreTests {
    private let database: MailDatabase
    private let work = Account(id: AccountID(rawValue: "a1"), email: "me@work.example", color: .teal, service: .gmail)
    private let home = Account(id: AccountID(rawValue: "a2"), email: "me@example.com", color: .pink, service: .gmail)
    private let fetched = Date(timeIntervalSince1970: 1_800_000_000)
    private let photo = URL(string: "https://lh3.googleusercontent.com/a/dana=s160")!

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ContactPhotoStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(work)
        try database.save(home)
    }

    @Test func anyAccountsPhotoServesTheAddressWhateverItsCase() throws {
        try database.apply(
            StoreChanges(
                accountID: work.id,
                addressBook: AddressBook(
                    contacts: [Contact(name: "Noah", address: "noah@example.com")], fetchedAt: fetched)))
        try database.apply(
            StoreChanges(
                accountID: home.id,
                addressBook: AddressBook(
                    contacts: [
                        Contact(name: "Dana Levi", address: "Dana@Example.com"),
                        Contact(name: "Noah", address: "noah@example.com"),
                    ],
                    photos: ["dana@example.com": photo], fetchedAt: fetched)))
        #expect(try database.photoURL(for: "dana@example.com") == photo)
        #expect(try database.photoURL(for: "DANA@EXAMPLE.COM") == photo)
        #expect(try database.photoURL(for: "noah@example.com") == nil)
        #expect(try database.photoURL(for: "stranger@example.com") == nil)
    }

    @Test func aNewAddressBookDropsAPhotoTheServiceNoLongerHas() throws {
        let dana = Contact(name: "Dana Levi", address: "dana@example.com")
        try database.apply(
            StoreChanges(
                accountID: home.id,
                addressBook: AddressBook(contacts: [dana], photos: ["dana@example.com": photo], fetchedAt: fetched)))
        try database.apply(
            StoreChanges(accountID: home.id, addressBook: AddressBook(contacts: [dana], fetchedAt: fetched)))
        #expect(try database.photoURL(for: "dana@example.com") == nil)
    }
}
