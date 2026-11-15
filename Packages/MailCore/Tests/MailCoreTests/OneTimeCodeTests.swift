import Testing

@testable import MailCore

/// A mail's one-time code is found with the words that name it, so an alert can show both and iOS offers the code
/// above the keyboard.
struct OneTimeCodeTests {
    @Test(
        arguments: [
            (
                "Your verification code is 482913. It expires in 10 minutes.", "482913",
                "Your verification code is 482913"
            ),
            ("482913 is your Instagram code. Don't share it.", "482913", "482913 is your Instagram code"),
            ("G-482913 is your Google verification code.", "G-482913", "G-482913 is your Google verification code"),
            (
                "Hi Idan,\n\nUse this code to sign in to Acme:\n\n  482913\n\nIf this wasn't you, ignore this mail.",
                "482913", "Use this code to sign in to Acme: 482913"
            ),
            ("Your one-time password: 7Q4K2X", "7Q4K2X", "Your one-time password: 7Q4K2X"),
            ("Enter PIN 9921 to confirm your purchase.", "9921", "Enter PIN 9921"),
            ("שלום, קוד האימות שלך הוא 482913. הוא בתוקף ל-10 דקות.", "482913", "קוד האימות שלך הוא 482913"),
        ])
    func aCodeIsFoundWithTheWordsThatNameIt(text: String, code: String, passage: String) throws {
        let found = try #require(OneTimeCode(in: text))
        #expect(found.code == code)
        #expect(found.passage == passage)
    }

    @Test(
        arguments: [
            "Your order 48291377 has shipped.",
            "Use promo code SAVE20 for 20% off.",
            "Your code expires in 10 minutes.",
            "Verify your address to finish signing up. © 2026 Acme",
            "Call us at 555-0134 about your account.",
        ])
    func numbersNoCodeWordNamesAreNotCodes(text: String) {
        #expect(OneTimeCode(in: text) == nil)
    }

    @Test func aMailCanNameACodeItDoesNotShowYet() {
        #expect(OneTimeCode.isNamed(in: "Your Acme sign-in code. Hi Idan, use the code below to sign in"))
        #expect(OneTimeCode.isNamed(in: "קוד כניסה לחשבון"))
        #expect(!OneTimeCode.isNamed(in: "Lunch tomorrow? Bring the promo code"))
        #expect(!OneTimeCode.isNamed(in: "Lunch tomorrow?"))
    }

    @Test func theBodyIsReadAsTextWhetherPlainOrHTML() {
        #expect(MessageBody(html: "<p>Code: <b>482913</b></p>", plain: "").text == "Code: 482913")
        #expect(MessageBody(html: "<p>ignored</p>", plain: "Code: 482913").text == "Code: 482913")
        #expect(MessageBody().text.isEmpty)
    }
}
