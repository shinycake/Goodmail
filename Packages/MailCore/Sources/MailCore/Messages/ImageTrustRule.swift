import Foundation

/// Mail whose remote images load without asking: everything from one address, or from every address at a domain.
/// Values are kept normalized (lowercase, no surrounding space), so two rules for the same mail compare equal.
public enum ImageTrustRule: Hashable, Codable, Sendable {
    /// Mail from exactly this address.
    case sender(String)
    /// Mail from any address at this domain, and at the domains under it when `subdomains` includes them.
    case domain(String, subdomains: Subdomains)

    /// Whether a domain rule reaches the domains under it: `mail.shop.example` under `shop.example`.
    public enum Subdomains: String, Codable, Sendable {
        case included
        case excluded
    }

    /// A rule for `address`, or `nil` unless it reads as `name@domain.tld`.
    public init?(sender address: String) {
        let address = Self.normalized(address)
        guard let (local, domain) = Self.split(address), !local.isEmpty, !local.contains(where: \.isWhitespace),
            Self.isDomain(domain)
        else { return nil }
        self = .sender(address)
    }

    /// A rule for `domain`, typed as a reader would: an `@` or `*.` in front and a trailing dot are dropped. `nil` for
    /// anything that isn't a domain with a name under its top level, since `com` would trust half the world.
    public init?(domain: String, subdomains: Subdomains) {
        var domain = Self.normalized(domain)
        for prefix in ["@", "*."] where domain.hasPrefix(prefix) { domain.removeFirst(prefix.count) }
        if domain.hasSuffix(".") { domain.removeLast() }
        guard Self.isDomain(domain) else { return nil }
        self = .domain(domain, subdomains: subdomains)
    }

    /// What a rule names. A reader keeps one rule for each address or domain.
    public enum Kind: Hashable, CaseIterable, Sendable {
        case sender
        case domain
    }

    public var kind: Kind {
        switch self {
        case .sender: .sender
        case .domain: .domain
        }
    }

    /// The address or domain the rule names.
    public var value: String {
        switch self {
        case .sender(let address): address
        case .domain(let domain, _): domain
        }
    }

    public func matches(_ address: String) -> Bool {
        let address = Self.normalized(address)
        switch self {
        case .sender(let trusted):
            return address == trusted
        case .domain(let trusted, let subdomains):
            guard let (_, domain) = Self.split(address) else { return false }
            return switch subdomains {
            case .excluded: domain == trusted
            case .included: domain == trusted || domain.hasSuffix("." + trusted)
            }
        }
    }

    /// Whether this is a domain anyone can get an address at, like `gmail.com`, so trusting it trusts strangers.
    public var isPublicMail: Bool {
        guard case .domain(let domain, _) = self else { return false }
        return Self.publicMailDomains.contains(domain)
    }

    /// The rules the reader may make from a message by `address`: the sender, and their domain with its subdomains.
    /// A public mail domain is left out, and an address that doesn't parse offers nothing.
    public static func offers(for address: String) -> [ImageTrustRule] {
        guard let sender = ImageTrustRule(sender: address), let (_, domain) = split(sender.value) else { return [] }
        let domainRule = ImageTrustRule.domain(String(domain), subdomains: .included)
        return domainRule.isPublicMail ? [sender] : [sender, domainRule]
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The local part and domain, split at the last `@`.
    private static func split(_ address: String) -> (local: Substring, domain: Substring)? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        return (address[..<at], address[address.index(after: at)...])
    }

    /// Two or more non-empty labels, with no spaces or `@`.
    private static func isDomain(_ domain: Substring) -> Bool {
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { !$0.isEmpty }
            && !domain.contains { $0.isWhitespace || $0 == "@" }
    }

    private static func isDomain(_ domain: String) -> Bool { isDomain(domain[...]) }
}

extension Sequence<ImageTrustRule> {
    /// Whether any of these rules loads remote images in mail from `address`.
    public func trust(_ address: String) -> Bool {
        contains { $0.matches(address) }
    }
}
