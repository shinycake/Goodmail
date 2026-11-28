import MailCore

extension Signpost {
    /// From a conversation's reader being made to a message's page in it laying out (`ThreadViewController`). It times
    /// a reader opening onto its pages. The chat layout shows bubbles rather than pages, and a reader can close before
    /// a page loads, so it can stay open; a reader switched from chat to pages, or loaded again after an error, ends it
    /// late, with the time the reader spent before.
    static let threadOpen = Signpost("ThreadOpen")
}
