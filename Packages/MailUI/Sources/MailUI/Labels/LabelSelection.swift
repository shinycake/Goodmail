import MailCore

/// Which user labels a set of threads carries, as the label picker shows and edits it.
struct LabelSelection: Equatable {
    enum State: Equatable {
        case on, off
        /// Some of the threads carry it. Left alone unless the user picks a side.
        case mixed
    }

    struct Choice: Equatable, Identifiable {
        let label: MailLabel
        var state: State
        var id: String { label.id }
    }

    private(set) var choices: [Choice]
    private let initial: [String: State]

    /// The account's visible user labels, in its order, with their state across `threads`.
    init(labels: [MailLabel], threads: [ThreadSummary]) {
        choices = labels.filter { $0.kind == .user && !$0.isHidden }.map { label in
            let carrying = threads.count { $0.labelIDs.contains(label.id) }
            let state: State = carrying == 0 ? .off : carrying == threads.count ? .on : .mixed
            return Choice(label: label, state: state)
        }
        initial = Dictionary(uniqueKeysWithValues: choices.map { ($0.id, $0.state) })
    }

    /// A tap turns a label on, or off when it already is.
    mutating func toggle(_ id: String) {
        guard let index = choices.firstIndex(where: { $0.id == id }) else { return }
        choices[index].state = choices[index].state == .on ? .off : .on
    }

    /// What applies the changes, or nil when there are none.
    var action: ThreadAction? {
        var add: Set<String> = []
        var remove: Set<String> = []
        for choice in choices where choice.state != initial[choice.id] {
            switch choice.state {
            case .on: add.insert(choice.id)
            case .off: remove.insert(choice.id)
            case .mixed: break
            }
        }
        return add.isEmpty && remove.isEmpty ? nil : .modifyLabels(add: add, remove: remove)
    }
}
