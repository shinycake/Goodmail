import Foundation
import ImageIO
import MailCore

/// Company senders' logos for alerts, fetched from the company's own website and kept in the App Group. People and
/// free-mail addresses get none, so their initials show instead and no lookup service learns who writes to the
/// reader. A domain's site is asked at most once a month, never about a particular message.
public struct SenderLogos: Sendable {
    /// A logo is fetched again after this long, so a rebrand shows up.
    static let freshFor: TimeInterval = 30 * 86_400
    /// A site without a usable logo is asked again after this long.
    static let missingFor: TimeInterval = 7 * 86_400
    /// Smaller icons look blurry at an alert's size.
    static let smallestSide = 60

    private let directory: URL
    private let http: any HTTPClient
    private let now: @Sendable () -> Date

    public init(
        directory: URL, http: any HTTPClient = URLSession.shared, now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.directory = directory
        self.http = http
        self.now = now
    }

    /// The sender's company logo as image data, or `nil` when there is none to show. A logo past its month is still
    /// shown while its site can't give a new one.
    public func logo(for address: String) async -> Data? {
        guard let domain = Self.domain(for: address) else { return nil }
        let logo = directory.appending(path: "\(domain).png")
        let missing = directory.appending(path: "\(domain).none")
        let cached = try? Data(contentsOf: logo)
        if let cached, isFresh(logo, for: Self.freshFor) { return cached }
        if isFresh(missing, for: Self.missingFor) { return cached }
        guard let data = await fetch(from: domain) else {
            remember(Data(), at: missing)
            return cached
        }
        remember(data, at: logo)
        return data
    }

    /// The domain whose site has the sender's logo: the registrable domain, as `github.com` for
    /// `noreply@mail.github.com`, or `nil` for a free-mail or malformed address.
    static func domain(for address: String) -> String? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        let labels = address[address.index(after: at)...].lowercased().split(separator: ".").map(String.init)
        guard labels.count >= 2, labels.allSatisfy(isHostLabel) else { return nil }
        // Country-code domains like example.co.il and example.com.au register one level deeper.
        let secondLevel = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or"]
        let deeper =
            labels.count >= 3 && labels[labels.count - 1].count == 2
            && secondLevel.contains(labels[labels.count - 2])
        let domain = labels.suffix(deeper ? 3 : 2).joined(separator: ".")
        return freeMail.contains(domain) ? nil : domain
    }

    private static func isHostLabel(_ label: String) -> Bool {
        !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// Addresses anyone can sign up for, whose domain's logo says nothing about the sender.
    static let freeMail: Set<String> = [
        "gmail.com", "googlemail.com", "icloud.com", "me.com", "mac.com", "outlook.com", "hotmail.com", "live.com",
        "msn.com", "yahoo.com", "ymail.com", "aol.com", "proton.me", "protonmail.com", "pm.me", "gmx.com", "gmx.net",
        "gmx.de", "web.de", "mail.com", "zoho.com", "yandex.com", "yandex.ru", "fastmail.com", "hey.com",
        "tutanota.com", "walla.co.il", "walla.com",
    ]

    private func fetch(from domain: String) async -> Data? {
        guard let url = URL(string: "https://\(domain)/apple-touch-icon.png") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("image/png,image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await http.data(for: request), response.statusCode == 200,
            Self.isUsableImage(data)
        else { return nil }
        return data
    }

    static func isUsableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return false }
        return min(width, height) >= smallestSide
    }

    private func isFresh(_ file: URL, for age: TimeInterval) -> Bool {
        guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return false }
        return now().timeIntervalSince(modified) < age
    }

    /// Best effort: a logo that can't be cached is fetched again next time.
    private func remember(_ data: Data, at file: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: file.path)
    }
}
