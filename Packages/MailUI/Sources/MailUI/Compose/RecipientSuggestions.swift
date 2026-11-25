import MailCore

/// The people offered under the recipient being typed, and the lookup that finds them. A list belongs to the text it
/// was found for: once more is typed, it stays on show until the new lookup answers, and Tab or Return pressed
/// meanwhile wait for that answer rather than add someone found for the earlier text. Only the methods below change
/// the state, each through `transition(to:)`, which stops a lookup it replaces and has the list on show drawn.
final class RecipientSuggestions {
    /// Which key asks to add someone from the list: Return only the person picked with Up or Down, so a typed
    /// address that also matches someone else stays as typed; Tab the picked one or else the first.
    enum CompletionKey: Equatable {
        case returnKey
        case tab
    }

    enum State {
        case hidden
        /// Looking up the people for `query`, typed under `field`, with the list found for earlier text still on
        /// show, if any, and the key pressed meanwhile, which the answer settles.
        case looking(
            for: String, under: RecipientField, Task<Void, Never>, showing: SuggestionList?, pending: CompletionKey?)
        /// `list` found for `query`, typed under `field`.
        case shown(SuggestionList, under: RecipientField, for: String)

        var lookup: Task<Void, Never>? {
            guard case .looking(_, _, let lookup, _, _) = self else { return nil }
            return lookup
        }

        /// The list on show and the field it is under.
        var onShow: OnShow? {
            switch self {
            case .hidden, .looking(_, _, _, showing: nil, _): nil
            case .looking(_, let field, _, showing: let list?, _), .shown(let list, let field, _): (list, field)
            }
        }
    }

    typealias OnShow = (list: SuggestionList, field: RecipientField)

    private(set) var state = State.hidden
    /// Draws the list now on show in place of the one before.
    private let draw: (_ now: OnShow?, _ before: OnShow?) -> Void
    /// Presses a key that waited for a lookup, once it answered, in its field.
    private let press: (CompletionKey, RecipientField) -> Void

    init(
        draw: @escaping (_ now: OnShow?, _ before: OnShow?) -> Void,
        press: @escaping (CompletionKey, RecipientField) -> Void
    ) {
        self.draw = draw
        self.press = press
    }

    isolated deinit {
        if case .looking(_, _, let lookup, _, _) = state { lookup.cancel() }
    }

    /// Looks up the people for `query`, just typed under `field`, with `find`.
    func look(for query: String, under field: RecipientField, find: @escaping () async -> [Contact]) {
        let lookup = Task { [weak self, weak field] in
            let contacts = await find()
            guard !Task.isCancelled, let self, let field else { return }
            found(contacts, for: query, under: field)
        }
        let stale = state.onShow.flatMap { $0.field === field ? $0.list : nil }
        transition(to: .looking(for: query, under: field, lookup, showing: stale, pending: nil))
    }

    /// The lookup for `query` answered: its people are listed, the one picked before kept picked, and a key pressed
    /// while it ran is pressed now.
    private func found(_ contacts: [Contact], for query: String, under field: RecipientField) {
        guard case .looking(query, let awaited, _, let stale, let pending) = state, awaited === field else { return }
        let list = SuggestionList(contacts, keeping: stale?.picked)
        transition(to: list.map { .shown($0, under: field, for: query) } ?? .hidden)
        if let pending { press(pending, field) }
    }

    func hide() {
        transition(to: .hidden)
    }

    /// Whether `key` in `field`, where `typed` is typed, goes to the list rather than to the text or the next field:
    /// Up and Down while a list found for `typed` shows, Tab also while the list for earlier text waits on a lookup.
    func takes(_ key: RecipientTextField.SuggestionKey, under field: RecipientField, typed: String) -> Bool {
        if current(under: field, typed: typed) != nil { return true }
        guard key == .tab, case .looking(_, let looking, _, showing: .some(_), _) = state else { return false }
        return looking === field
    }

    /// The list under `field`, while it was found for what is typed there now.
    func current(under field: RecipientField, typed: String) -> SuggestionList? {
        guard case .shown(let list, let under, let query) = state, under === field, query == typed else { return nil }
        return list
    }

    /// Up or Down moves the highlight in the list found for what is typed in `field`.
    func move(_ step: SuggestionList.Step, under field: RecipientField, typed: String) {
        guard var list = current(under: field, typed: typed) else { return }
        list.move(step)
        transition(to: .shown(list, under: field, for: typed))
    }

    /// Keeps `key` for the lookup under way in `field` to settle, when its answer decides it: Tab while a list shows,
    /// Return while someone is picked in it. Returns whether it waits.
    func wait(_ key: CompletionKey, under field: RecipientField) -> Bool {
        guard case .looking(let query, let looking, let lookup, let stale?, _) = state, looking === field else {
            return false
        }
        switch key {
        case .tab: break
        case .returnKey: guard stale.picked != nil else { return false }
        }
        transition(to: .looking(for: query, under: field, lookup, showing: stale, pending: key))
        return true
    }

    /// The one place `state` changes: a lookup the next state doesn't carry on is stopped, and the list on show is
    /// drawn.
    private func transition(to next: State) {
        let before = state
        if let lookup = before.lookup, lookup != next.lookup { lookup.cancel() }
        state = next
        draw(next.onShow, before.onShow)
    }
}
