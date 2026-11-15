import MailCore

/// An account's labels nested by their paths, as `Projects/Goodmail` sits under `Projects`. A step of a path that
/// is no label itself, as Gmail allows and IMAP's `\Noselect` folders are, is a folder that only holds the rest.
nonisolated struct LabelTree: Equatable {
    struct Node: Equatable {
        /// The last step of the path, as the row shows it.
        let name: String
        /// The whole path.
        let path: String
        /// `nil` for a step that is no label.
        let label: MailboxDirectory.Label?
        let children: [Node]
    }

    let roots: [Node]

    /// `labels` are one account's, in the order to show them; a parent keeps the place of its first label.
    init(_ labels: [MailboxDirectory.Label]) {
        roots = Self.nodes(labels.map { (steps: $0.name.split(separator: "/").map(String.init), label: $0) }, under: [])
    }

    private static func nodes(
        _ labels: [(steps: [String], label: MailboxDirectory.Label)], under parent: [String]
    ) -> [Node] {
        var order: [String] = []
        var byStep: [String: [(steps: [String], label: MailboxDirectory.Label)]] = [:]
        for entry in labels {
            let step = entry.steps.first ?? entry.label.name
            if byStep[step] == nil { order.append(step) }
            byStep[step, default: []].append(entry)
        }
        return order.map { step in
            let entries = byStep[step] ?? []
            let path = parent + [step]
            let own = entries.first { $0.steps.count <= 1 }?.label
            let deeper = entries.filter { $0.steps.count > 1 }.map {
                (steps: Array($0.steps.dropFirst()), label: $0.label)
            }
            return Node(
                name: step, path: path.joined(separator: "/"), label: own, children: nodes(deeper, under: path))
        }
    }
}
