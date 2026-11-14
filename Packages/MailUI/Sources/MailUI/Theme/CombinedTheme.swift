import MailCore

/// What a view that spans accounts, such as the unified inbox, wears: the reader's choice in Settings.
public enum CombinedTheme: Equatable, Sendable {
    /// A gradient through every account's color. The standard.
    case gradient
    /// One color the reader picked instead.
    case solid(AccountColor)
}
