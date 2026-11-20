extension ChatTranscript {
    /// The words a letter shows in full where no web view can, as on the watch. A message that answers an earlier one
    /// shows its own words, without the history it quotes, which the conversation already holds. Anything else, such
    /// as a newsletter, and a forward, whose history is what it says, shows its whole body.
    public static func letterWords(of message: Message) -> StyledText {
        let whole = message.body.styledText
        let reply = ReplyText(body: message.body)
        guard !message.references.isEmpty, !reply.forwards else { return whole }
        let own = reply.segments.compactMap { segment -> StyledText? in
            if case .text(let text) = segment { text } else { nil }
        }
        let words = MessageBody.tidied(StyledText.joined(own, separator: "\n\n"))
        return words.isEmpty ? whole : words
    }
}
