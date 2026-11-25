public import Foundation
public import Observation

/// A reply written on the watch. It's held for a moment after Send, so Undo can take it back, and then goes to the
/// iPhone, which sends it.
@MainActor @Observable
public final class WristReplyModel {
    /// A reply waiting out its moment before it goes.
    public struct Held: Equatable, Sendable {
        public let id = UUID()
        public let text: String
    }

    public enum State: Equatable, Sendable {
        case writing
        case holding(Held)
        case sent(String)
    }

    public private(set) var state: State = .writing
    /// The moment a reply is held for. It throws when cancelled, as when the reader leaves the screen; the reply then
    /// goes at once, since only Undo takes it back.
    private let hold: @Sendable () async throws -> Void
    private let deliver: @MainActor (String) -> Void

    public init(
        hold: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(4)) },
        deliver: @escaping @MainActor (String) -> Void
    ) {
        self.hold = hold
        self.deliver = deliver
    }

    /// The reply being held, for whoever runs `release` while it is.
    public var held: Held? {
        guard case .holding(let held) = state else { return nil }
        return held
    }

    /// Holds `text` for Undo; `release` sends it after. Blank text, or a reply already on its way, does nothing.
    public func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, state == .writing else { return }
        state = .holding(Held(text: text))
    }

    /// Waits out the moment `held` is held for, then sends it unless Undo took it back first. Cancelled, as when the
    /// reader leaves the screen, it sends at once.
    public func release(_ held: Held) async {
        guard state == .holding(held) else { return }
        try? await hold()
        guard state == .holding(held) else { return }
        state = .sent(held.text)
        deliver(held.text)
    }

    /// Sends the held reply now, without waiting out its moment, as when the app goes to the background, where it
    /// may be suspended or ended before the moment is over.
    public func releaseNow() {
        guard case .holding(let held) = state else { return }
        state = .sent(held.text)
        deliver(held.text)
    }

    /// Takes back the held reply, and returns its words to write again; `nil` when nothing is held.
    public func undo() -> String? {
        guard case .holding(let held) = state else { return nil }
        state = .writing
        return held.text
    }
}
