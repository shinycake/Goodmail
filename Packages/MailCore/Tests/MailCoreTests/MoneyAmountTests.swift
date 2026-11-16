import Foundation
import Testing

@testable import MailCore

/// Sums of money are read out of mail, so Shortcuts can sort orders by price without a model reading them.
struct MoneyAmountTests {
    @Test(
        arguments: [
            ("Your order of $24.99 has shipped.", "24.99", "USD"),
            ("Total: USD 1,234.50", "1234.5", "USD"),
            ("Prix : 24,99 €", "24.99", "EUR"),
            ("Betrag 1.234,56 EUR", "1234.56", "EUR"),
            ("סה״כ לתשלום: 120 ₪", "120", "ILS"),
            ("שילמת 89.90 ש״ח", "89.9", "ILS"),
            ("£5 off your next order", "5", "GBP"),
            ("¥3000", "3000", "JPY"),
            ("Charged C$12.00 to your card", "12", "CAD"),
        ])
    func anAmountIsReadWithItsCurrency(text: String, value: String, currency: String) throws {
        let amount = try #require(MoneyAmount.all(in: text).first)
        #expect(amount.value == Decimal(string: value))
        #expect(amount.currency == currency)
    }

    @Test(arguments: ["Order 112-4829137-5527400 has shipped.", "Call 555-0134", "Meet at 10.30", "Version 2.5"])
    func numbersWithoutACurrencyAreNotAmounts(text: String) {
        #expect(MoneyAmount.all(in: text).isEmpty)
    }

    @Test func everyAmountIsFoundInOrder() {
        let text = "Echo Dot $49.99\nUSB-C cable $9.99\nShipping $0.00"
        #expect(MoneyAmount.all(in: text).map(\.value) == [Decimal(string: "49.99"), Decimal(string: "9.99"), 0])
    }

    @Test func theTotalIsTheLastLineThatSaysItIs() throws {
        let receipt = """
            Echo Dot $49.99
            Subtotal: $59.98
            Tax $5.10
            Order Total: $65.08
            """
        let total = try #require(MoneyAmount.total(in: receipt))
        #expect(total.value == Decimal(string: "65.08"))
    }

    @Test func aHebrewTotalIsFound() throws {
        let total = try #require(MoneyAmount.total(in: "מוצר א 50 ₪\nסה\"כ 150 ₪"))
        #expect(total.value == 150)
        #expect(total.currency == "ILS")
    }

    @Test func noTotalLineMeansNoTotal() {
        #expect(MoneyAmount.total(in: "Echo Dot $49.99") == nil)
    }

    @Test(arguments: [("1,234", "1234"), ("1.234,5", "1234.5"), ("12,50", "12.5"), ("1 234", "1234"), ("7", "7")])
    func separatorsAreReadAsGroupingOrDecimalPoint(number: String, value: String) {
        #expect(MoneyAmount.decimal(number) == Decimal(string: value))
    }
}
