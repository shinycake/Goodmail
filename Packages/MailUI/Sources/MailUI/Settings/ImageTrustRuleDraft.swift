import MailCore

/// A trust rule as the editor's fields hold it while it's typed: what it names, the text, and for a domain whether
/// its subdomains count. Switching between sender and domain keeps the text, so a typo isn't lost.
struct ImageTrustRuleDraft: Equatable {
    var kind: ImageTrustRule.Kind
    var text: String
    var subdomains: ImageTrustRule.Subdomains

    /// An empty domain rule that reaches subdomains, the rule a reader most often adds by hand.
    init() {
        kind = .domain
        text = ""
        subdomains = .included
    }

    init(_ rule: ImageTrustRule) {
        kind = rule.kind
        text = rule.value
        subdomains =
            switch rule {
            case .sender: .included
            case .domain(_, let subdomains): subdomains
            }
    }

    /// The rule the fields make, or `nil` while they don't make one, which keeps Save off.
    var rule: ImageTrustRule? {
        switch kind {
        case .sender: ImageTrustRule(sender: text)
        case .domain: ImageTrustRule(domain: text, subdomains: subdomains)
        }
    }
}
