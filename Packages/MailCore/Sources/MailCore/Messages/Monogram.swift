/// The initials that stand in for a sender's picture.
public enum Monogram {
    /// Up to two initials from the first letters of the first two words: "Dana Levi" → "DL", "יעל כהן" → "יכ".
    public static func initials(for name: String) -> String {
        let words = name.split { $0.isWhitespace || $0 == "@" || $0 == "." }
        let letters = words.prefix(2).compactMap { $0.first(where: \.isLetter) }
        return String(letters).uppercased()
    }
}
