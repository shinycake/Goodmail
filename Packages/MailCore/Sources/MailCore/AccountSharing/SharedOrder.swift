/// The places a device shares for its accounts, ranked among every shared account rather than only its own, so two
/// devices with different accounts agree on them instead of renumbering each other's records every round.
enum SharedOrder {
    /// `local` is this device's accounts in order; `shared` the other shared accounts' places. Where this device's
    /// order agrees with the shared one, the shared order stands, with this device's new accounts after their
    /// neighbor; otherwise this device's order wins, and the accounts it doesn't have follow their shared neighbor.
    static func places(of local: [AccountID], shared: [AccountID: Int]) -> [AccountID: Int] {
        let sharedOrder = shared.sorted { ($0.value, $0.key.rawValue) < ($1.value, $1.key.rawValue) }.map(\.key)
        let here = Set(local)
        let agrees = local.filter { shared[$0] != nil } == sharedOrder.filter(here.contains)
        let merged = agrees ? merge(local, into: sharedOrder) : merge(sharedOrder, into: local)
        return Dictionary(uniqueKeysWithValues: merged.enumerated().map { ($1, $0) })
    }

    /// `base`, with each of `other`'s accounts it lacks placed after the one before it in `other`, or first.
    private static func merge(_ other: [AccountID], into base: [AccountID]) -> [AccountID] {
        var merged = base
        var previous: AccountID?
        for id in other {
            if !merged.contains(id) {
                let at = previous.flatMap { merged.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                merged.insert(id, at: at)
            }
            previous = id
        }
        return merged
    }
}
