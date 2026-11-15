import CryptoKit
import Foundation
import MailCore

/// The profile photos the accounts' address books keep for people, as Gmail shows beside their mail, kept in the App
/// Group by photo URL. A changed photo comes with a new URL on the next address-book sync, so a kept one never goes
/// stale.
public struct ProfilePhotos: Sendable {
    private let directory: URL
    private let http: any HTTPClient
    private let photoURL: @Sendable (String) -> URL?

    /// `photoURL` gives the photo an address book keeps for an address, if any.
    public init(
        directory: URL, http: any HTTPClient = URLSession.shared, photoURL: @escaping @Sendable (String) -> URL?
    ) {
        self.directory = directory
        self.http = http
        self.photoURL = photoURL
    }

    /// The person's photo, or `nil` when no address book has one or it can't be fetched now.
    public func photo(for address: String) async -> Data? {
        guard let url = photoURL(address) else { return nil }
        let file = directory.appending(path: Self.fileName(for: url))
        if let kept = try? Data(contentsOf: file) { return kept }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await http.data(for: request), response.statusCode == 200,
            SenderLogos.isUsableImage(data)
        else { return nil }
        // Best effort: a photo that can't be kept is fetched again next time.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }

    /// The URL's digest: photo URLs are long and full of characters file names can't hold.
    static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".photo"
    }
}
