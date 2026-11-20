import MailCore
import UIKit

/// A letter the find bar can search. Each open letter is a web view of its own (ADR-003), so the conversation is
/// searched one letter at a time.
@MainActor
protocol FindTarget: UIView {
    /// The next match of `query` from the one this letter shows, as a box in the letter's own coordinates.
    func findMatch(_ query: String, backwards: Bool) async -> CGRect?
    /// Forgets the match the letter shows.
    func clearMatch() async
}

extension MessageCardView: FindTarget {}

/// Find in the open conversation: what the bar says and which letter holds the match now. `FindOrder` says where each
/// search goes next. The bar and the scrolling follow `state`, and every change to it is made here.
@MainActor
final class ConversationFind {
    enum Outcome: Equatable {
        /// Nothing searched yet, or the field is empty.
        case idle
        /// The match shows in this letter.
        case found(ObjectIdentifier)
        case notFound
    }

    enum State: Equatable {
        case closed
        case open(query: String, outcome: Outcome)
    }

    private(set) var state = State.closed {
        didSet { if state != oldValue { onChange?(state) } }
    }
    /// The letters that are open, in reading order.
    var targets: () -> [any FindTarget] = { [] }
    /// A match was found in a letter, at a box in that letter's coordinates, and the conversation should show it.
    var onMatch: ((any FindTarget, CGRect) -> Void)?
    var onChange: ((State) -> Void)?
    /// The search that runs now. A newer one, or closing, cancels it.
    private var search: Task<Void, Never>?

    deinit {
        search?.cancel()
    }

    var isOpen: Bool { state != .closed }

    /// Whether Find Next and Find Previous have something to find.
    var canStep: Bool {
        guard case .open(let query, _) = state else { return false }
        return !query.isEmpty
    }

    func open() {
        guard state == .closed else { return }
        state = .open(query: "", outcome: .idle)
    }

    /// The field's text changed: search again from the top.
    func setQuery(_ query: String) {
        guard isOpen else { return }
        search?.cancel()
        state = .open(query: query, outcome: .idle)
        if query.isEmpty {
            clearAll()
        } else {
            run(query, from: nil, backwards: false)
        }
    }

    /// Goes to the next or the previous match, over the letters and round again.
    func step(backwards: Bool) {
        guard case .open(let query, let outcome) = state, !query.isEmpty else { return }
        var current: ObjectIdentifier?
        if case .found(let id) = outcome { current = id }
        run(query, from: current, backwards: backwards)
    }

    func close() {
        search?.cancel()
        state = .closed
        clearAll()
    }

    private func clearAll() {
        let targets = targets()
        search = Task {
            for target in targets { await target.clearMatch() }
        }
    }

    private func run(_ query: String, from current: ObjectIdentifier?, backwards: Bool) {
        search?.cancel()
        let targets = targets()
        let at = current.flatMap { id in targets.firstIndex { ObjectIdentifier($0) == id } }
        search = Task {
            // A new search starts clean, so no letter keeps a match of the last words.
            if at == nil { for target in targets { await target.clearMatch() } }
            for attempt in FindOrder.attempts(from: at, count: targets.count, backwards: backwards) {
                guard !Task.isCancelled else { return }
                let target = targets[attempt.view]
                if !attempt.continuesSelection { await target.clearMatch() }
                guard let box = await target.findMatch(query, backwards: backwards) else { continue }
                guard !Task.isCancelled else { return }
                if let at, targets[at] !== target { await targets[at].clearMatch() }
                state = .open(query: query, outcome: .found(ObjectIdentifier(target)))
                onMatch?(target, box)
                return
            }
            guard !Task.isCancelled else { return }
            state = .open(query: query, outcome: .notFound)
        }
    }
}
