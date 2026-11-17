/// The short answers the watch offers above dictation. They're written in the conversation's language rather than
/// the watch's, since they go to the other person: Hebrew when the message being answered is in Hebrew.
public enum WristQuickReplies {
    public static let english = [
        "Thanks!", "Sounds good.", "On my way.", "Yes", "No", "Can't talk now. I'll get back to you soon.",
    ]
    public static let hebrew = ["תודה!", "נשמע טוב.", "בדרך.", "כן", "לא", "לא יכול לדבר עכשיו, אחזור אליך בקרוב."]

    /// The answers for `thread`, by the language of the newest message from someone else.
    public static func answers(for thread: WristThread) -> [String] {
        let answered = thread.bubbles.last { $0.side == .theirs }?.content.text ?? thread.subject
        return isHebrew(answered) ? hebrew : english
    }

    /// Whether the first letter of `text` is Hebrew.
    static func isHebrew(_ text: String) -> Bool {
        guard let letter = text.unicodeScalars.first(where: \.properties.isAlphabetic) else { return false }
        return (0x0590...0x05FF).contains(letter.value)
    }
}
