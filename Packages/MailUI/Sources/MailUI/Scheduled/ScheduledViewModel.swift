import Foundation
import MailCore
import Observation

/// Messages waiting to go at a time the writer picked, soonest first. They live only on this device until they go.
@Observable
public final class ScheduledViewModel: WaitingListModel {
    public private(set) var content = WaitingContent<Draft.ID>.loading

    @ObservationIgnored private let messages: () -> AsyncThrowingStream<[OutgoingMessage], any Error>
    @ObservationIgnored private let accounts: [Account]
    @ObservationIgnored private let actions: MailActions

    public init(
        accounts: [Account], messages: @escaping () -> AsyncThrowingStream<[OutgoingMessage], any Error>,
        actions: MailActions
    ) {
        self.accounts = accounts
        self.messages = messages
        self.actions = actions
    }

    /// Follows the store until the calling task is cancelled. A failure leaves the last list in place.
    public func observe() async {
        do {
            for try await messages in messages() { content = .loaded(messages.map(row(for:))) }
        } catch {}
    }

    /// Opens the message in the composer; it waits no longer until it is sent or scheduled again.
    public func open(_ id: Draft.ID) {
        actions.editScheduled(id)
    }

    /// Keeps the message in Drafts instead of sending it.
    public func takeBack(_ id: Draft.ID) {
        actions.unschedule(id)
    }

    private func row(for message: OutgoingMessage) -> WaitingRow<Draft.ID> {
        let draft = message.draft
        let recipients = (draft.to + draft.cc + draft.bcc).map(\.displayName)
        let color = accounts.count > 1 ? accounts.first { $0.id == draft.accountID }?.color : nil
        return WaitingRow(
            id: draft.id,
            title: recipients.formatted(.list(type: .and, width: .short)),
            subtitle: draft.subject.isEmpty
                ? String(localized: "No Subject", bundle: .module, comment: "Shown for a message without a subject")
                : draft.subject,
            time: ScheduledTime.text(for: message.sendAt),
            accountColor: color)
    }
}
