import MailCore
import MailNotifications
import MailStore
import MailUI
import os

/// Apply Rules, Block Sender and VIPs for every window (ADR-038), done off the main actor. What fails is logged:
/// nothing in it is the reader's to fix.
extension AppModel {
    func senderRulesService() -> SenderRules.Service {
        let database = database
        return SenderRules.Service(
            applyRules: { [weak self] in await self?.applyRules(to: $0) },
            block: { sender, name in
                do {
                    try await Self.offMain { try database.block(sender, named: name) }
                } catch {
                    RuleRun.log.error("Block Sender couldn't write its rule: \(error, privacy: .public)")
                }
            },
            setVIP: { sender, isVIP in
                do {
                    try await Self.offMain { try database.setVIP(sender, isVIP) }
                } catch {
                    RuleRun.log.error("The VIPs couldn't be changed: \(error, privacy: .public)")
                }
            },
            vips: { database.vipList() })
    }
}
