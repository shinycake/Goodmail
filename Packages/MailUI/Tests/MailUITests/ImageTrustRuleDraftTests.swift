import MailCore
import Testing

@testable import MailUI

/// The rule editor's fields make a rule only once they hold a valid address or domain, and keep what was typed when
/// the reader switches between the two.
@MainActor
struct ImageTrustRuleDraftTests {
    @Test func aNewDraftIsAnEmptyDomainWithSubdomainsAndSavesNothing() {
        let draft = ImageTrustRuleDraft()
        #expect(draft.kind == .domain)
        #expect(draft.subdomains == .included)
        #expect(draft.rule == nil)
    }

    @Test(arguments: [
        ImageTrustRule.sender("news@shop.example"), .domain("shop.example", subdomains: .excluded),
        .domain("shop.example", subdomains: .included),
    ])
    func editingARuleStartsFromIt(_ rule: ImageTrustRule) {
        #expect(ImageTrustRuleDraft(rule).rule == rule)
    }

    @Test func switchingKindKeepsTheTextAndRevalidatesIt() {
        var draft = ImageTrustRuleDraft()
        draft.text = "News@Shop.Example"
        #expect(draft.rule == nil, "an address isn't a domain")
        draft.kind = .sender
        #expect(draft.rule == .sender("news@shop.example"))
    }

    @Test func theSubdomainChoiceShapesADomainRule() {
        var draft = ImageTrustRuleDraft()
        draft.text = "shop.example"
        draft.subdomains = .excluded
        #expect(draft.rule == .domain("shop.example", subdomains: .excluded))
    }
}
