import Foundation
public import MailCore
public import Observation
internal import SwiftUI

/// The reader's mail rules as Settings shows them: read each time the screen appears, changed in place, and saved
/// after each change in the order the changes were made.
@MainActor
@Observable
public final class MailRules {
    /// How Settings reads and stores the rules, and which label names to suggest.
    public struct Service {
        public let load: () async throws -> [MailRule]
        public let save: ([MailRule]) async throws -> Void
        /// The reader's labels and folders, by name, across the accounts.
        public let labelNames: () async -> [String]
        /// Every read and save made through this service, one after another, whichever screen asked: a screen opened
        /// again reads only once the saves the one before it asked for have run.
        let order = TaskChain()

        public init(
            load: @escaping () async throws -> [MailRule], save: @escaping ([MailRule]) async throws -> Void,
            labelNames: @escaping () async -> [String]
        ) {
            self.load = load
            self.save = save
            self.labelNames = labelNames
        }
    }

    enum State: Equatable {
        case loading
        /// The rules as the reader has them; `saveFailure` is why the last save didn't go through, shown until the
        /// reader dismisses it.
        case loaded([MailRule], saveFailure: String?)
        case failed
    }

    private(set) var state: State = .loading
    private(set) var labelNames: [String] = []
    @ObservationIgnored private let service: Service

    public init(service: Service) {
        self.service = service
    }

    /// Reads the rules and label names again, after every save asked for before (`Service.order`), so the rules
    /// changed on another device show and a save still under way is never read back as undone. Rules already shown
    /// stay up while they are read, and a read that fails leaves them.
    func load() async {
        if case .failed = state { state = .loading }
        // A change made from here on is saved after this read, which can't see it, so the read keeps it as shown.
        let before = shownRules
        service.order.run { [self] in
            do {
                let read = try await service.load()
                switch state {
                case .loaded(let shown, let failure):
                    state = .loaded(shown == before ? read : shown, saveFailure: failure)
                case .loading, .failed:
                    state = .loaded(read, saveFailure: nil)
                }
            } catch {
                if case .loading = state { state = .failed }
            }
            labelNames = await service.labelNames()
        }
        await service.order.settled()
    }

    func save(_ rule: MailRule) {
        change { rules in
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[index] = rule
            } else {
                rules.append(rule)
            }
        }
    }

    func setEnabled(_ enabled: Bool, for id: MailRule.ID) {
        change { rules in
            guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
            rules[index].isEnabled = enabled
        }
    }

    func remove(at offsets: IndexSet) {
        change { $0.remove(atOffsets: offsets) }
    }

    func move(from offsets: IndexSet, to destination: Int) {
        change { $0.move(fromOffsets: offsets, toOffset: destination) }
    }

    /// Why the last save didn't go through, for the alert.
    var saveFailure: String? {
        if case .loaded(_, let failure) = state { failure } else { nil }
    }

    /// The reader read why the save failed.
    func dismissSaveFailure() {
        guard case .loaded(let rules, .some) = state else { return }
        state = .loaded(rules, saveFailure: nil)
    }

    /// Waits for every save asked for so far, as a test does.
    func settled() async {
        await service.order.settled()
    }

    private var shownRules: [MailRule]? {
        if case .loaded(let rules, _) = state { rules } else { nil }
    }

    /// Shows `edit` at once and stores the rules after the saves before it. Each save stores the rules as they are
    /// when its turn comes, so the last change is what stays.
    private func change(_ edit: (inout [MailRule]) -> Void) {
        guard case .loaded(var rules, let failure) = state else { return }
        edit(&rules)
        state = .loaded(rules, saveFailure: failure)
        service.order.run { [self] in
            guard case .loaded(let rules, _) = state else { return }
            do {
                try await service.save(rules)
            } catch {
                guard case .loaded(let shown, _) = state else { return }
                state = .loaded(shown, saveFailure: error.localizedDescription)
            }
        }
    }
}
