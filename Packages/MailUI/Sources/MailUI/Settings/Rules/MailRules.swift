import Foundation
public import MailCore
public import Observation
internal import SwiftUI

/// The reader's mail rules as Settings shows them: loaded once, changed in place, and saved after each change in the
/// order the changes were made.
@MainActor
@Observable
public final class MailRules {
    /// How Settings reads and stores the rules, and which label names to suggest.
    public struct Service {
        public let load: () async throws -> [MailRule]
        public let save: ([MailRule]) async throws -> Void
        /// The reader's labels and folders, by name, across the accounts.
        public let labelNames: () async -> [String]

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
        case loaded([MailRule])
        case failed
    }

    private(set) var state: State = .loading
    private(set) var labelNames: [String] = []
    /// A save that failed, shown until the reader dismisses it.
    var saveError: String?
    @ObservationIgnored private let service: Service
    @ObservationIgnored private let saves = TaskChain()

    public init(service: Service) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await service.load())
        } catch {
            state = .failed
        }
        labelNames = await service.labelNames()
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

    /// Waits for every save asked for so far, as a test does.
    func settled() async {
        await saves.settled()
    }

    /// Shows `edit` at once and stores the rules after the saves before it. Each save stores the rules as they are
    /// when its turn comes, so the last change is what stays.
    private func change(_ edit: (inout [MailRule]) -> Void) {
        guard case .loaded(var rules) = state else { return }
        edit(&rules)
        state = .loaded(rules)
        saves.run { [self] in
            guard case .loaded(let rules) = state else { return }
            do {
                try await service.save(rules)
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
