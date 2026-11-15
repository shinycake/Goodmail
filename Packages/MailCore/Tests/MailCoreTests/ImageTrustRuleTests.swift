import MailCore
import Testing

/// A trust rule loads remote images in mail from one address, or from every address at a domain and, when the reader
/// chooses, its subdomains.
struct ImageTrustRuleTests {
    @Test func aSenderRuleMatchesOnlyThatAddressInAnyCase() throws {
        let rule = try #require(ImageTrustRule(sender: " News@Shop.Example "))
        #expect(rule == .sender("news@shop.example"))
        #expect(rule.matches("NEWS@shop.example"))
        #expect(!rule.matches("deals@shop.example"))
        #expect(!rule.matches("news@shop.example.evil"))
    }

    @Test(arguments: ["", "  ", "shop.example", "@shop.example", "news@", "news@shop", "a b@shop.example"])
    func anIncompleteAddressMakesNoSenderRule(_ address: String) {
        #expect(ImageTrustRule(sender: address) == nil)
    }

    @Test(arguments: [
        ("shop.example", "shop.example"), (" Shop.Example. ", "shop.example"), ("@shop.example", "shop.example"),
        ("*.shop.example", "shop.example"), ("mail.shop.co.il", "mail.shop.co.il"),
    ])
    func domainsAreTypedLeniently(_ typed: String, _ domain: String) throws {
        let rule = try #require(ImageTrustRule(domain: typed, subdomains: .included))
        #expect(rule == .domain(domain, subdomains: .included))
    }

    @Test(arguments: ["", "com", "news@shop.example", "shop..example", ".example", "shop example.com"])
    func aMalformedOrTopLevelDomainMakesNoRule(_ typed: String) {
        #expect(ImageTrustRule(domain: typed, subdomains: .included) == nil)
    }

    @Test func aDomainRuleMatchesItsAddressesAndItsSubdomainsOnlyWhenIncluded() {
        let exact = ImageTrustRule.domain("shop.example", subdomains: .excluded)
        let wide = ImageTrustRule.domain("shop.example", subdomains: .included)
        #expect(exact.matches("news@Shop.Example"))
        #expect(!exact.matches("news@mail.shop.example"))
        #expect(wide.matches("news@shop.example"))
        #expect(wide.matches("news@mail.shop.example"))
        #expect(!wide.matches("news@evilshop.example"), "a subdomain is a whole label, not a suffix")
        #expect(!wide.matches("shop.example@evil.example"))
        #expect(!wide.matches(""))
    }

    @Test func theReaderIsOfferedTheSenderAndTheirDomainWithSubdomains() {
        #expect(
            ImageTrustRule.offers(for: "News@Mail.Shop.Example") == [
                .sender("news@mail.shop.example"), .domain("mail.shop.example", subdomains: .included),
            ])
    }

    @Test(arguments: ["anna@gmail.com", "anna@iCloud.com", "anna@outlook.co.il", "anna@walla.co.il"])
    func aPublicMailDomainIsNeverOffered(_ address: String) {
        #expect(ImageTrustRule.offers(for: address).count == 1)
        let domain = String(address.split(separator: "@")[1])
        #expect(ImageTrustRule(domain: domain, subdomains: .excluded)?.isPublicMail == true)
    }

    @Test func aSenderWithNoAddressIsOfferedNothing() {
        #expect(ImageTrustRule.offers(for: "").isEmpty)
    }

    @Test func rulesTrustAnAddressWhenAnyMatches() {
        let rules: [ImageTrustRule] = [.sender("anna@example.com"), .domain("shop.example", subdomains: .included)]
        #expect(rules.trust("deals@news.shop.example"))
        #expect(rules.trust("Anna@example.com"))
        #expect(!rules.trust("bob@example.com"))
    }
}
