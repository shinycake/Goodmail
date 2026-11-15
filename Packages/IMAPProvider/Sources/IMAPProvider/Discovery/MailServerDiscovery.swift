import Foundation
import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Finds an address's IMAP and SMTP servers, as Thunderbird does (Mozilla's autoconfig): the provider's own
/// configuration file first, then Mozilla's database of providers (ISPDB). When neither knows the domain, as for a
/// custom domain hosted elsewhere, the domain's own SRV records (RFC 6186) come next, then ISPDB is asked again for
/// the domains of its mail exchangers (MX), which names the host. The domain, never the address, goes to Mozilla
/// and to the DNS resolver.
public struct MailServerDiscovery: Sendable {
    /// The body at a URL when it answers 200, else `nil`.
    private let fetch: @Sendable (URL) async throws -> Data?

    public init() {
        self.init { url in
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue("application/xml, application/json", forHTTPHeaderField: "Accept")
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
        if let found = await firstFile(at: Self.sources(for: address), for: address) { return found }
        let dns = DNSRecords(fetch: fetch)
        return await Self.first([
            { await Self.serviceSettings(for: address, dns: dns) },
            { await exchangerSettings(for: address, dns: dns) },
        ])
    }

    /// The first file, in the order of `urls`, that names usable servers for `address`.
    private func firstFile(at urls: [URL], for address: Address) async -> MailServerSettings? {
        await Self.first(
            urls.map { url in
                { [fetch] in (try? await fetch(url)).flatMap { AutoconfigFile(parsing: $0)?.settings(for: address) } }
            })
    }

    /// ISPDB's servers for the domains of the address's most preferred mail exchanger.
    private func exchangerSettings(for address: Address, dns: DNSRecords) async -> MailServerSettings? {
        guard let host = await dns.mailExchangers(of: address.domain).first else { return nil }
        let domains = Self.parentDomains(of: host).filter { $0 != address.domain }
        return await firstFile(at: domains.compactMap(Self.databaseURL), for: address)
    }

    /// The servers the domain's SRV records name (RFC 6186): IMAP and SMTP submission, TLS from the first byte
    /// preferred over STARTTLS (RFC 8314). The user name is the whole address, as RFC 6186 says.
    static func serviceSettings(for address: Address, dns: DNSRecords) async -> MailServerSettings? {
        async let imaps = dns.services("_imaps._tcp.\(address.domain)").first
        async let imap = dns.services("_imap._tcp.\(address.domain)").first
        async let submissions = dns.services("_submissions._tcp.\(address.domain)").first
        async let submission = dns.services("_submission._tcp.\(address.domain)").first
        let (tls, plain, tlsSubmission, plainSubmission) = await (imaps, imap, submissions, submission)
        let incoming = tls.map { $0.server(.tls) } ?? plain.map { $0.server(.startTLS) }
        let outgoing = tlsSubmission.map { $0.server(.tls) } ?? plainSubmission.map { $0.server(.startTLS) }
        guard let incoming, let outgoing else { return nil }
        return MailServerSettings(imap: incoming, smtp: outgoing, username: address.email)
    }

    /// A host's parent domains of two labels or more, longest first, so `mx01.mail.icloud.com` gives
    /// `mail.icloud.com` and then `icloud.com`. A public suffix such as `co.uk` among them is harmless: ISPDB has
    /// no entry for it.
    static func parentDomains(of host: String) -> [String] {
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return [] }
        return (1...(labels.count - 2)).map { labels[$0...].joined(separator: ".") }
    }

    /// The first answer, in the order of `attempts`, that isn't `nil`. Every attempt starts at once, and the result
    /// comes as soon as every better-ranked one has answered.
    private static func first(
        _ attempts: [@Sendable () async -> MailServerSettings?]
    ) async -> MailServerSettings? {
        await withTaskGroup(of: (Int, MailServerSettings?).self) { group in
            for (rank, attempt) in attempts.enumerated() {
                group.addTask { (rank, await attempt()) }
            }
            var found: [Int: MailServerSettings] = [:]
            var answered = Set<Int>()
            for await (rank, settings) in group {
                answered.insert(rank)
                if let settings { found[rank] = settings }
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
            URL(string: "https://autoconfig.\(domain)/mail/config-v1.1.xml?emailaddress=\(email)"),
            URL(string: "https://\(domain)/.well-known/autoconfig/mail/config-v1.1.xml"),
            databaseURL(for: domain),
        ].compactMap { $0 }
    }

    /// The domain's entry in Mozilla's ISPDB.
    static func databaseURL(for domain: String) -> URL? {
        URL(string: "https://autoconfig.thunderbird.net/v1.1/\(domain)")
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
