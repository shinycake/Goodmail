import Foundation

/// The domain a sender's mail comes from, for finding the brand picture it publishes: the address's host, and the
/// registrable domain that host belongs to.
public struct SenderDomain: Hashable, Sendable {
    /// The whole host after the `@`, lowercased: `mail.github.com`.
    public let host: String
    /// The registrable domain, as `github.com` for `mail.github.com` and `example.co.il` for `shop.example.co.il`.
    public let organization: String

    /// `nil` for a malformed address, and for a public mail provider's, whose brand says nothing about the sender.
    public init?(address: String) {
        guard let at = address.lastIndex(of: "@") else { return nil }
        let host = address[address.index(after: at)...].lowercased()
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count >= 2, labels.allSatisfy(Self.isHostLabel) else { return nil }
        // Country-code domains like example.co.il and example.com.au register one level deeper. A heuristic, not
        // the Public Suffix List: good enough to pick where a logo lives.
        let secondLevel: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or"]
        let deeper =
            labels.count >= 3 && labels[labels.count - 1].count == 2
            && secondLevel.contains(labels[labels.count - 2])
        let organization = labels.suffix(deeper ? 3 : 2).joined(separator: ".")
        guard !ImageTrustRule.publicMailDomains.contains(organization),
            !ImageTrustRule.publicMailDomains.contains(host)
        else { return nil }
        self.host = host
        self.organization = organization
    }

    /// Where BIMI records are looked up, in order: the host's, then its organization's (RFC draft
    /// "Brand Indicators for Message Identification", section 4.6). The first that exists decides.
    public var bimiRecordNames: [String] {
        let names = [host, organization].map { "default._bimi.\($0)" }
        return host == organization ? [names[0]] : names
    }

    private static func isHostLabel(_ label: String) -> Bool {
        !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
