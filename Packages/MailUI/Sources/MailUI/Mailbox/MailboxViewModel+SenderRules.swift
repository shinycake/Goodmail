import MailCore

extension MailboxViewModel {
    /// The one person the threads `ids` are all from, other than the reader on any of their accounts, for Block Sender
    /// and VIPs; `nil` when they are from several, or a thread isn't listed.
    func sender(of ids: [ThreadSummary.ID]) -> SenderAddress? {
        let wanted = Set(ids)
        let threads = sections.flatMap(\.threads).filter { wanted.contains($0.id) }
        guard threads.count == wanted.count else { return nil }
        let own = accounts.values.flatMap { [$0.email] + $0.aliases.map(\.address) }
        return SenderAddress.shared(by: threads.map(\.sender), notFrom: own)
    }
}
