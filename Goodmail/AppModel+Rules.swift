import MailCore
import MailNotifications
import MailStore
import MailUI
import OSLog

/// The reader's mail rules, run on what each sync brings (`RuleRunner`). The notification extension runs them too,
/// on what a push brings; each message goes through them once, in whichever process stores it first.
extension AppModel {
    /// Runs the rules on each account's new mail, and posts the notifications they ask for. An account whose rules
    /// can't run, or an action that fails, is logged; the others still run.
    func runRules(for accounts: [Account]) async {
        for account in accounts {
            do {
                let runner = RuleRunner(
                    store: database, provider: try providers.provider(for: account.id), commands: commands)
                let run = try await runner.run(for: account.id)
                run.logFailures(after: "a sync")
                if !run.alerts.isEmpty { await RuleNotification.post(run.alerts, in: account) }
            } catch {
                RuleRun.log.error("Rules after a sync failed: \(error, privacy: .public)")
            }
        }
    }

    /// How Settings reads and stores the rules, off the main actor, and which label names it suggests.
    func rulesService() -> MailRules.Service {
        let database = database
        return MailRules.Service(
            load: { try await Self.offMain { try database.rules() } },
            save: { rules in try await Self.offMain { try database.setRules(rules) } },
            labelNames: { [accounts] in
                let names = try? await Self.offMain {
                    try accounts.flatMap { try database.labels(for: $0.id) }.filter { $0.kind == .user && !$0.isHidden }
                        .map(\.name)
                }
                return Array(Set(names ?? [])).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            })
    }
}
