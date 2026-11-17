import Foundation

/// A one-time code a mail carries, as for signing in or confirming an address, with the words that name it.
///
/// iOS offers a code above the keyboard when an alert's text gives it with words that say it's a code, so an alert
/// for a mail whose code is past its snippet shows `passage` instead.
public struct OneTimeCode: Equatable, Sendable {
    public let code: String
    /// The code and the words naming it, on one line, as "Your verification code is 482913".
    public let passage: String

    /// The first code in `text` that words next to it name as one: after them in the same sentence, as "Your code
    /// is 482913", or just before them, as "482913 is your code".
    public init?(in text: String) {
        for word in Self.codeWords(in: text) {
            if let found = Self.code(after: word, in: text) ?? Self.code(before: word, in: text) {
                self = found
                return
            }
        }
        return nil
    }

    /// Whether `text` names a code at all, as a subject that says one follows in the body does.
    public static func isNamed(in text: String) -> Bool {
        codeWords(in: text).first != nil
    }

    // MARK: - Finding it

    /// Words that name a code, in English and Hebrew.
    private static var codeWord: Regex<Substring> {
        /(?i)\b(?:codes?|passcode|otp|pin|one[- ]time password|verification|verify)\b|קוד|אימות/
    }

    /// Words that, just before "code", make it something other than a one-time code.
    private static let otherCodes: Set<String> = [
        "promo", "promotional", "discount", "coupon", "gift", "voucher", "referral", "zip", "postal", "area", "source",
    ]

    /// A code: 4 to 8 digits, one with a letter prefix as Google sends, or 6 to 8 capitals and digits with both.
    /// The token must stand alone, not be part of a longer number, a word or a phone number.
    private static var token: Regex<(Substring, Substring)> {
        /(?:^|[^\w-])((?:[A-Z]-[0-9]{4,8}|[0-9]{4,8}|(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]{6,8}))(?=$|[^\w-])/
    }

    /// A year, as in a copyright line, which is never a code.
    private static var year: Regex<Substring> { /(?:19|20)[0-9]{2}/ }

    private static let clauseEnd: Set<Character> = [".", "!", "?", "\n"]
    private static let clauseStart: Set<Character> = [".", "!", "?", "\n", ",", ";", ":"]

    /// How far from the words that name it a code can be.
    private static let reachAfter = 150
    private static let reachBefore = 40

    private static func codeWords(in text: String) -> [Range<String.Index>] {
        text.matches(of: codeWord).map(\.range).filter { word in
            let before = text[..<word.lowerBound].split(whereSeparator: \.isWhitespace).last
            return before.map { !otherCodes.contains($0.lowercased()) } ?? true
        }
    }

    /// The first code after `word`, up to the end of its sentence, with the sentence from its start.
    private static func code(after word: Range<String.Index>, in text: String) -> OneTimeCode? {
        let limit = text.index(word.upperBound, offsetBy: reachAfter, limitedBy: text.endIndex) ?? text.endIndex
        let sentenceEnd = text[word.upperBound..<limit].firstRange(of: /[.!?](?:\s|$)/)?.lowerBound ?? limit
        guard let code = codes(in: text[word.upperBound..<sentenceEnd]).first else { return nil }
        let start = text[..<word.lowerBound].lastIndex(where: clauseStart.contains).map(text.index(after:))
        return OneTimeCode(code: code, passage: text[(start ?? text.startIndex)..<code.endIndex])
    }

    /// The last code shortly before `word` in its clause, with the clause through its end.
    private static func code(before word: Range<String.Index>, in text: String) -> OneTimeCode? {
        let limit = text.index(word.lowerBound, offsetBy: -reachBefore, limitedBy: text.startIndex) ?? text.startIndex
        let start = text[limit..<word.lowerBound].lastIndex(where: clauseEnd.contains).map(text.index(after:))
        guard let code = codes(in: text[(start ?? limit)..<word.lowerBound]).last else { return nil }
        let end = text[word.upperBound...].firstIndex(where: clauseEnd.contains) ?? text.endIndex
        return OneTimeCode(code: code, passage: text[code.startIndex..<end])
    }

    private static func codes(in text: Substring) -> [Substring] {
        text.matches(of: token).map(\.output.1).filter { $0.wholeMatch(of: year) == nil }
    }

    private init(code: Substring, passage: Substring) {
        self.code = String(code)
        self.passage = passage.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
