import MailCore
import Testing

struct LinkAddressTests {
    @Test("A short address stays as it is")
    func short() {
        #expect(LinkAddress.shortened("https://example.com/a", limit: 40) == "https://example.com/a")
    }

    @Test("A long address loses its middle and keeps both ends within the limit")
    func long() {
        let address = "https://example.com/" + String(repeating: "x", count: 100) + "/end.html"
        let shown = LinkAddress.shortened(address, limit: 31)
        #expect(shown.count == 31)
        #expect(shown.hasPrefix("https://example"))
        #expect(shown.hasSuffix("xx/end.html"))
        #expect(shown.contains("…"))
    }

    @Test("An address exactly at the limit is whole")
    func exact() {
        #expect(LinkAddress.shortened("abcdef", limit: 6) == "abcdef")
        #expect(LinkAddress.shortened("abcdefg", limit: 6).count == 6)
    }

    @Test("A tiny limit still gives something")
    func tiny() {
        #expect(LinkAddress.shortened("abcdefg", limit: 1) == "…")
    }
}
