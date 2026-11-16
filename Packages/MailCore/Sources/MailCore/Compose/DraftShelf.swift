/// The messages a window has in progress: the one being written, and those minimized to the bottom of the screen to
/// come back to. `Composer` is whatever edits a draft, kept alive while it waits so nothing typed is lost.
///
/// Only the methods below change it, and each keeps `state` in step with `entries`: `.empty` exactly when there are
/// none, and `.writing` always names one of them.
public struct DraftShelf<Composer> {
    /// A message in progress, with the draft as it stood when it was last minimized.
    public struct Entry: Identifiable {
        public var id: Draft.ID { draft.id }
        public let composer: Composer
        public fileprivate(set) var draft: Draft
    }

    public enum State: Equatable, Sendable {
        /// Nothing in progress.
        case empty
        /// That draft fills the screen; any others wait minimized.
        case writing(Draft.ID)
        /// Every draft waits at the bottom of the screen.
        case minimized
        /// The drafts are laid out to pick one, after swiping up on several.
        case choosing
    }

    /// The drafts in progress, the last one written first.
    public private(set) var entries: [Entry] = []
    public private(set) var state: State = .empty

    public init() {}

    /// The draft filling the screen, if one is.
    public var writing: Entry? {
        guard case .writing(let id) = state else { return nil }
        return entries.first { $0.id == id }
    }

    /// Starts writing `draft` in `composer`, minimizing whatever was open. A draft already in progress is written in
    /// the composer it has.
    public mutating func open(_ draft: Draft, in composer: Composer) {
        if !entries.contains(where: { $0.id == draft.id }) {
            entries.insert(Entry(composer: composer, draft: draft), at: 0)
        }
        choose(draft.id)
    }

    /// Minimizes the draft being written, keeping it as `draft` shows it now.
    public mutating func minimize(_ draft: Draft) {
        guard state == .writing(draft.id), let index = entries.firstIndex(where: { $0.id == draft.id }) else {
            return
        }
        entries[index].draft = draft
        state = .minimized
    }

    /// Swiping up on the minimized drafts: a lone draft opens, several are laid out to pick from.
    public mutating func reopen() {
        guard state == .minimized, let first = entries.first else { return }
        if entries.count == 1 { choose(first.id) } else { state = .choosing }
    }

    /// Writes the draft `id`, bringing it to the front.
    public mutating func choose(_ id: Draft.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.insert(entries.remove(at: index), at: 0)
        state = .writing(id)
    }

    /// Puts the laid-out drafts back at the bottom of the screen.
    public mutating func dismissChoice() {
        guard state == .choosing else { return }
        state = .minimized
    }

    /// The draft `id` was sent, saved away or deleted, so it is no longer in progress.
    public mutating func finish(_ id: Draft.ID) {
        entries.removeAll { $0.id == id }
        if entries.isEmpty {
            state = .empty
        } else if state == .writing(id) || (state == .choosing && entries.count == 1) {
            // A single draft left needs no picking, so it goes back to the bar.
            state = .minimized
        }
    }
}

extension DraftShelf.Entry: Sendable where Composer: Sendable {}
extension DraftShelf: Sendable where Composer: Sendable {}
