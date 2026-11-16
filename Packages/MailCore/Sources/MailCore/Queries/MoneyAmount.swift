public import Foundation

/// A sum of money a mail's text names, as an order confirmation's "$24.99" or a receipt's "סה״כ 120 ₪". Shortcuts
/// and rules filter and sort on it, so "what I ordered last week, by price" needs no model to read the mail.
public struct MoneyAmount: Hashable, Codable, Sendable {
    public var value: Decimal
    /// ISO 4217, when the text names the currency: `$` reads as USD, `₪` as ILS.
    public var currency: String?

    public init(value: Decimal, currency: String?) {
        self.value = value
        self.currency = currency
    }

    /// Every amount `text` names, in order.
    public static func all(in text: String) -> [MoneyAmount] {
        let before = text.matches(of: symbolFirst).map { ($0.range, $0.output.1, $0.output.2) }
        let after = text.matches(of: numberFirst).map { ($0.range, $0.output.2, $0.output.1) }
        return (before + after).sorted { $0.0.lowerBound < $1.0.lowerBound }.compactMap { _, symbol, number in
            decimal(String(number)).map { MoneyAmount(value: $0, currency: currency(for: String(symbol))) }
        }
    }

    /// The amount a line that says it is the total names, as "Order total: $54.20". When several lines do, as a
    /// subtotal before a grand total, the last one wins: receipts end with what was paid.
    public static func total(in text: String) -> MoneyAmount? {
        text.split(whereSeparator: \.isNewline).reversed().lazy.compactMap { line -> MoneyAmount? in
            guard let word = line.firstRange(of: totalWord) else { return nil }
            return all(in: String(line[word.lowerBound...])).first
        }.first
    }

    // MARK: - Reading it

    /// A currency symbol or code, then a number, as `$24.99` or `USD 24.99`.
    private static var symbolFirst: Regex<(Substring, Substring, Substring)> {
        /(?i)(US\$|C\$|A\$|[$€£¥₪₹]|\b(?:USD|EUR|GBP|ILS|NIS|JPY|CAD|AUD|INR|CHF)\b)\s?([0-9]{1,3}(?:[,. ][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)(?![0-9])/
    }

    /// A number, then the currency, as `24,99 €` or `120 ₪`. The number starts the text or follows a character that
    /// can't be part of it.
    private static var numberFirst: Regex<(Substring, Substring, Substring)> {
        /(?i)(?:^|[^0-9.,$€£¥₪₹])([0-9]{1,3}(?:[,. ][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)\s?([€₪]|ש"ח|ש״ח|\b(?:USD|EUR|GBP|ILS|NIS|JPY|CAD|AUD|INR|CHF)\b)/
    }

    /// The words a total's line starts with, in English and Hebrew.
    private static var totalWord: Regex<Substring> {
        /(?i)\b(?:grand total|order total|total|amount paid|amount due|you paid|charged)\b|סה"כ|סה״כ|סך הכל|לתשלום/
    }

    /// The number with its grouping taken out. The last separator is the decimal point when one or two digits follow
    /// it, as in `1.234,56` or `24.99`; otherwise every separator groups thousands, as in `1,234`.
    static func decimal(_ number: String) -> Decimal? {
        let separators: Set<Character> = [",", ".", " "]
        var digits = number
        if let last = number.lastIndex(where: separators.contains), number[last] != " ",
            (1...2).contains(number.distance(from: last, to: number.endIndex) - 1)
        {
            let whole = number[..<last].filter { !separators.contains($0) }
            digits = whole + "." + number[number.index(after: last)...]
        } else {
            digits = number.filter { !separators.contains($0) }
        }
        return Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func currency(for symbol: String) -> String? {
        switch symbol.uppercased() {
        case "$", "US$", "USD": "USD"
        case "C$", "CAD": "CAD"
        case "A$", "AUD": "AUD"
        case "€", "EUR": "EUR"
        case "£", "GBP": "GBP"
        case "¥", "JPY": "JPY"
        case "₪", "ILS", "NIS", "ש\"ח", "ש״ח": "ILS"
        case "₹", "INR": "INR"
        case "CHF": "CHF"
        default: nil
        }
    }
}
