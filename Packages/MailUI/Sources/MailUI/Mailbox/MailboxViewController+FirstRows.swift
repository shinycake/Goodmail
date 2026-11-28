import MailCore

extension MailboxViewController {
    /// The list was built: the `MailboxFirstRows` interval starts. A controller whose view never loads, as a search's
    /// list before any search, never starts one.
    func noteListBuilt() {
        firstRows.begin()
    }

    /// The list's snapshot holds what the store answered, its first rows or that it has none: the interval ends, and
    /// so does the launch, if this list answered first. The cells lay out and draw in the next layout pass, after it.
    func noteListShown() {
        guard viewModel.listing.hasAnswered, firstRows.end() else { return }
        LaunchInterval.end()
    }
}

extension Signpost {
    static let mailboxFirstRows = Signpost("MailboxFirstRows")
}
