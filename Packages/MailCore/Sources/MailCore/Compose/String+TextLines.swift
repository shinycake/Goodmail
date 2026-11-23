extension String {
    /// The text's lines, however they end. Mail off the wire ends them with CRLF, which Swift reads as one character,
    /// never a "\n", so splitting on "\n" alone leaves its lines joined.
    var textLines: [Substring] {
        split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }
}
