import MailCore
import MailNotifications
import MailStore
import MailUI
import OSLog

/// The reader's mail rules, run on what each sync brings (`RuleRunner`). The notification extension runs them too,
/// on what a push brings; each message goes through them once, in whichever process stores it first. A Mac runs
/// them on all of it as it comes, an iPhone or iPad a batch at a time (`RuleCatchUp`, ADR-038).
extension AppModel {
    /// Runs the rules on each account's new mail, and posts the notifications they ask for. An account whose rules
    /// can't run, or an action that fails, is logged; the others still run.
    func runRules(for accounts: [Account]) async {
        let catchUp = RuleCatchUp(PresenceTracker.shared.policy)
        for account in accounts {
            await runRules(in: account, after: "a sync") { try await $0.run(for: account.id, catchingUp: catchUp) }
        }
    }

    /// Apply Rules: runs the rules on the picked conversations, each account's with its own provider, and posts the
    /// notifications they ask for, as a sync's run does.
    func applyRules(to threads: [ThreadSummary.ID]) async {
        for (id, picked) in Dictionary(grouping: threads, by: \.accountID) {
            guard let account = accounts.first(where: { $0.id == id }) else { continue }
            await runRules(in: account, after: "Apply Rules") { try await $0.apply(to: picked) }
        }
    }

    /// Runs `run` with a runner for `account`, then posts its alerts and logs what failed.
    private func runRules(
        in account: Account, after occasion: String, _ run: (RuleRunner) async throws -> RuleRun
    ) async {
        do {
            let provider = try await providers.provider(madeFor: account.id)
            let outcome = try await run(RuleRunner(store: database.blocking, provider: provider, commands: commands))
            outcome.logFailures(after: occasion)
            if !outcome.alerts.isEmpty { await RuleNotification.post(outcome.alerts, in: account) }
        } catch {
            RuleRun.log.error("Rules after \(occasion, privacy: .public) failed: \(error, privacy: .public)")
        }
    }

    /// How Settings reads and stores the rules, off the main actor, and which label names it suggests from the
    /// accounts there are when it asks. Made once, as `rulesService`.
    func makeRulesService() -> MailRules.Service {
        let database = database
        return MailRules.Service(
            load: { try await database.offMain { try $0.rules() } },
            save: { rules in try await database.offMain { try $0.setRules(rules) } },
            labelNames: { [weak self] in
                let accounts = self?.accounts ?? []
                let names = try? await database.offMain { database in
                    try accounts.flatMap { try database.labels(for: $0.id) }.filter { $0.kind == .user && !$0.isHidden }
                        .map(\.name)
                }
                return Array(Set(names ?? [])).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            })
    }
}
