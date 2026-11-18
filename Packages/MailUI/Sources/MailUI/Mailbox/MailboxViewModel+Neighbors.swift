import MailCore

extension MailboxViewModel {
    /// The thread `offset` rows from `id` in the list as it shows, across its sections, for Next and Previous
    /// Message. From no thread, going down starts at the first row. `nil` past either end.
    func thread(_ offset: Int, from id: ThreadSummary.ID?) -> ThreadSummary.ID? {
        let ids = sections.flatMap(\.threads).map(\.id)
        guard let id, let index = ids.firstIndex(of: id) else { return offset > 0 ? ids.first : nil }
        let target = index + offset
        return ids.indices.contains(target) ? ids[target] : nil
    }
}
