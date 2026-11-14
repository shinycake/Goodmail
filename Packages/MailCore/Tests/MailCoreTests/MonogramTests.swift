import Testing

@testable import MailCore

struct MonogramTests {
    @Test func monogramsTakeTwoInitialsInAnyScript() {
        #expect(Monogram.initials(for: "Dana Levi") == "DL")
        #expect(Monogram.initials(for: "יעל כהן") == "יכ")
        #expect(Monogram.initials(for: "\"Ann\" Marie Smith") == "AM")
        #expect(Monogram.initials(for: "noreply@shop.example") == "NS")
        #expect(Monogram.initials(for: "") == "")
    }
}
