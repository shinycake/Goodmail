import MailCore
import MailStore
import MailUI

/// The reader's smart mailboxes (ADR-039) and the VIPs box's VIPs (ADR-038), stored off the main actor and shared with their other devices
/// as soon as they change.
extension AppModel {
    func smartMailboxStore() -> SmartMailboxStore {
        let database = database
        return SmartMailboxStore(
            box: { id in try await Self.offMain { try database.smartMailboxes().first { $0.id == id } } },
            vips: { try await Self.offMain { try database.vips() } },
            save: { [weak self] box, vips in
                try await Self.offMain { try database.saveSmartMailbox(box, vips: vips) }
                self?.shareSettingsNow()
            },
            delete: { [weak self] id in
                try await Self.offMain { try database.deleteSmartMailbox(id) }
                self?.shareSettingsNow()
            },
            labelNames: rulesService.labelNames)
    }
}
