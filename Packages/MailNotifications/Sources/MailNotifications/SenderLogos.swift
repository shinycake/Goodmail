import Foundation
import ImageIO
import MailCore

/// Company senders' logos, kept in the App Group: the logo the domain publishes for mail clients through BIMI, as
/// Gmail and Apple Mail show, or else its website's touch icon. People and public mail providers' addresses get none,
/// so their initials show instead. Each domain is asked at most once a month, never about a particular message, and
/// DNS goes through the system resolver.
///
/// BIMI's mark certificates aren't checked yet. Mail claiming a domain must pass that domain's DMARC policy, which
/// BIMI requires to be enforcing, so a spoofed sender is rejected before it arrives; a look-alike domain can publish
/// its own record, as it can its own touch icon.
public struct SenderLogos: Sendable {
    /// A logo is fetched again after this long, so a rebrand shows up.
    static let freshFor: TimeInterval = 30 * 86_400
    /// A domain without a usable logo is asked again after this long.
    static let missingFor: TimeInterval = 7 * 86_400
    /// Smaller icons look blurry at an alert's size.
    static let smallestSide = 60
    /// BIMI logos are drawn at this many pixels square: sharp at an alert's or a row's size on a 3x screen.
    static let renderedSide = 256
    /// BIMI caps a logo at 32 KB; anything much bigger isn't one.
    static let largestSVG = 128 * 1024

    private let directory: URL
    private let http: any HTTPClient
    private let dns: any TXTResolving
    private let now: @Sendable () -> Date

    public init(
        directory: URL, http: any HTTPClient = URLSession.shared, dns: any TXTResolving = SystemTXTResolver(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.directory = directory
        self.http = http
        self.dns = dns
        self.now = now
    }

    /// The sender's company logo as PNG data, or `nil` when there is none to show. A logo past its month is still
    /// shown while its domain can't give a new one.
    public func logo(for address: String) async -> Data? {
        guard let domain = SenderDomain(address: address) else { return nil }
        let logo = directory.appending(path: "\(domain.host).png")
        let missing = directory.appending(path: "\(domain.host).none")
        let cached = try? Data(contentsOf: logo)
        if let cached, isFresh(logo, for: Self.freshFor) { return cached }
        if isFresh(missing, for: Self.missingFor) { return cached }
        var fetched = await bimiLogo(of: domain)
        if fetched == nil { fetched = await siteIcon(of: domain.organization) }
        guard let data = fetched else {
            remember(Data(), at: missing)
            return cached
        }
        remember(data, at: logo)
        return data
    }

    /// The domain's BIMI logo, drawn as PNG. The host's record decides when it has one, else the organization's.
    private func bimiLogo(of domain: SenderDomain) async -> Data? {
        for name in domain.bimiRecordNames {
            guard let record = BIMIRecord(txtRecords: await dns.txtRecords(named: name)) else { continue }
            guard let url = record.logo else { return nil }
            var request = URLRequest(url: url, timeoutInterval: 4)
            request.setValue("image/svg+xml", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await http.data(for: request), response.statusCode == 200,
                data.count <= Self.largestSVG, let image = SVGDocument.image(from: data)
            else { return nil }
            return VectorRenderer.png(of: image, side: Self.renderedSide)
        }
        return nil
    }

    private func siteIcon(of domain: String) async -> Data? {
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
