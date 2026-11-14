import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Finds an address's IMAP and SMTP servers, as Thunderbird does (Mozilla's autoconfig): the provider's own
/// configuration file first, then Mozilla's database of providers (ISPDB). The domain, not the address, goes to
/// Mozilla. Every source is asked at once, and the first in that order that answers wins.
public struct MailServerDiscovery: Sendable {
    /// The body at a URL when it answers 200, else `nil`.
    private let fetch: @Sendable (URL) async throws -> Data?

    public init() {
        self.init { url in
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("application/xml", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200 ? data : nil
        }
    }

    init(fetch: @escaping @Sendable (URL) async throws -> Data?) {
        self.fetch = fetch
    }

    /// The servers for `email`, or `nil` when no source knows its domain.
    public func settings(for email: String) async -> MailServerSettings? {
        guard let address = Address(email) else { return nil }
        let sources = Self.sources(for: address)
        return await withTaskGroup(of: (Int, MailServerSettings?).self) { group in
            for (rank, url) in sources.enumerated() {
                group.addTask {
                    let data = try? await fetch(url)
                    return (rank, data.flatMap { AutoconfigFile(parsing: $0)?.settings(for: address) })
                }
            }
            var found: [Int: MailServerSettings] = [:]
            var answered = Set<Int>()
            for await (rank, settings) in group {
                answered.insert(rank)
                if let settings { found[rank] = settings }
                // Done as soon as every better-ranked source has answered.
                if let best = found.keys.min(), (0..<best).allSatisfy(answered.contains) {
                    group.cancelAll()
                    return found[best]
                }
            }
            return nil
        }
    }

    /// Where to look, best first (Thunderbird's autoconfig, as Mozilla documents it).
    static func sources(for address: Address) -> [URL] {
        let domain = address.domain
        let email = address.email.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
        return [
            "https://autoconfig.\(domain)/mail/config-v1.1.xml?emailaddress=\(email)",
            "https://\(domain)/.well-known/autoconfig/mail/config-v1.1.xml",
            "https://autoconfig.thunderbird.net/v1.1/\(domain)",
        ].compactMap(URL.init(string:))
    }

    /// A guess for an address no source knows, for the reader to correct: `imap.` and `smtp.` before its domain,
    /// on the ports with TLS.
    public static func guess(for email: String) -> MailServerSettings {
        let domain = Address(email)?.domain ?? ""
        return MailServerSettings(
            imap: MailServer(host: "imap.\(domain)", port: 993, security: .tls),
            smtp: MailServer(host: "smtp.\(domain)", port: 587, security: .startTLS),
            username: email.trimmingCharacters(in: .whitespaces))
    }
}

/// An email address split at its `@`.
struct Address: Equatable {
    var email: String
    var localPart: String
    var domain: String

    init?(_ text: String) {
        let email = text.trimmingCharacters(in: .whitespaces)
        guard let at = email.lastIndex(of: "@") else { return nil }
        let localPart = String(email[..<at])
        let domain = email[email.index(after: at)...].lowercased()
        guard !localPart.isEmpty, domain.contains("."), !domain.contains("/") else { return nil }
        self.email = email
        self.localPart = localPart
        self.domain = domain
    }
}

extension CharacterSet {
    fileprivate static let urlQueryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(["&", "=", "+", "?"])
}
