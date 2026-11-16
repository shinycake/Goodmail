public import Foundation
public import MailCore
public import Observation

/// One account's automatic reply as the reader edits it: loaded from the service, changed here, and saved back
/// when the reader taps Save. Every state change happens in `load()` or `save()`.
@Observable
public final class AutoReplyEditor {
    /// Where the editor stands with the service.
    public enum State: Equatable {
        case loading
        /// The service's reply, which `draft` started from.
        case editing(saved: AutoReply)
        case saving(saved: AutoReply)
        /// The service's reply couldn't be read, so there is nothing to edit.
        case loadFailed
    }

    /// What the service can do with a reply, and how to reach it.
    public struct Service {
        public let hasSubject: Bool
        public let load: () async throws -> AutoReply
        public let save: (AutoReply) async throws -> Void

        public init(
            hasSubject: Bool, load: @escaping () async throws -> AutoReply,
            save: @escaping (AutoReply) async throws -> Void
        ) {
            self.hasSubject = hasSubject
            self.load = load
            self.save = save
        }
    }

    public private(set) var state: State = .loading
    /// The reply as the reader has it now.
    public var draft = AutoReply()
    /// A save the service refused, shown until the reader dismisses it.
    public var saveError: String?
    @ObservationIgnored let service: Service
    @ObservationIgnored private let now: () -> Date

    public init(service: Service, now: @escaping () -> Date = Date.init) {
        self.service = service
        self.now = now
    }

    var isSaving: Bool {
        if case .saving = state { true } else { false }
    }

    /// Whether Save has anything to send.
    var hasChanges: Bool {
        guard case .editing(let saved) = state else { return false }
        return draft != saved
    }

    func load() async {
        guard state == .loading || state == .loadFailed else { return }
        state = .loading
        do {
            let reply = try await service.load()
            draft = reply
            state = .editing(saved: reply)
        } catch {
            state = .loadFailed
        }
    }

    func save() async {
        guard case .editing(let saved) = state, draft != saved else { return }
        let reply = draft
        state = .saving(saved: saved)
        do {
            try await service.save(reply)
            state = .editing(saved: reply)
        } catch {
            saveError = error.localizedDescription
            state = .editing(saved: saved)
        }
    }

    /// The reply runs: on until turned off, or between dates once the reader picks them.
    var isOn: Bool {
        get { draft.schedule != .off }
        set { draft.schedule = newValue ? .on : .off }
    }

    /// Whether the reply runs only between two dates. Turning it on starts with today until a week from now.
    var isScheduled: Bool {
        get { if case .between = draft.schedule { true } else { false } }
        set {
            guard newValue != isScheduled else { return }
            let start = Calendar.autoupdatingCurrent.startOfDay(for: now())
            draft.schedule = newValue ? .between(DateInterval(start: start, duration: 7 * 86_400)) : .on
        }
    }

    var start: Date {
        get { interval?.start ?? now() }
        set { draft.schedule = .between(DateInterval(start: newValue, end: max(newValue, end))) }
    }

    var end: Date {
        get { interval?.end ?? now() }
        set { draft.schedule = .between(DateInterval(start: min(start, newValue), end: newValue)) }
    }

    private var interval: DateInterval? {
        if case .between(let interval) = draft.schedule { interval } else { nil }
    }
}
