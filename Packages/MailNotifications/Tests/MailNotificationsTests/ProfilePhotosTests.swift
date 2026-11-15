import Foundation
import Testing

@testable import MailNotifications

struct ProfilePhotosTests {
    private let dana = URL(string: "https://lh3.googleusercontent.com/a-/dana=s160")!

    @Test func aPhotoIsFetchedOnceThenKept() async throws {
        let site = FakeSite(image: FakeSite.png(side: 160))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let photos = ProfilePhotos(directory: directory, http: site) { [dana] in
            $0 == "dana@example.com" ? dana : nil
        }

        #expect(await photos.photo(for: "dana@example.com") != nil)
        #expect(await photos.photo(for: "dana@example.com") != nil)
        #expect(site.urls == [dana.absoluteString])
    }

    @Test func noAddressBookPhotoAsksNothing() async {
        let site = FakeSite(image: FakeSite.png(side: 160))
        let photos = ProfilePhotos(directory: FileManager.default.temporaryDirectory, http: site) { _ in nil }
        #expect(await photos.photo(for: "noah@example.com") == nil)
        #expect(site.urls.isEmpty)
    }

    @Test func aBrokenImageIsntShownOrKept() async {
        let site = FakeSite(image: Data("<html>".utf8))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let photos = ProfilePhotos(directory: directory, http: site) { [dana] _ in dana }
        #expect(await photos.photo(for: "dana@example.com") == nil)
        #expect(await photos.photo(for: "dana@example.com") == nil)
        #expect(site.urls.count == 2)
    }
}
