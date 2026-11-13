import Foundation
import MailCore
import Observation

/// Messages waiting to go at a time the writer picked, soonest first. They live only on this device until they go.
@Observable
public final class ScheduledViewModel {
    nonisolated public struct Row: Hashable, Identifiable, Sendable {
        public let id: Draft.ID
        /// Who it goes to, by name where known.
        public let recipients: String
        public let subject: String
        /// When it goes.
        public let time: String
        /// The account it goes from, shown only when there is more than one.
        public let accountColor: AccountColor?
    }

    public enum Content: Equatable {
        /// The store hasn't been read yet, so an empty list isn't mistaken for no messages.
        case loading
        case loaded([Row])
    }

    public private(set) var content = Content.loading

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
    public func edit(_ id: Draft.ID) {
        actions.editScheduled(id)
    }

    /// Keeps the message in Drafts instead of sending it.
    public func unschedule(_ id: Draft.ID) {
        actions.unschedule(id)
    }

    private func row(for message: OutgoingMessage) -> Row {
        let draft = message.draft
        let recipients = (draft.to + draft.cc + draft.bcc).map(\.displayName)
        let color = accounts.count > 1 ? accounts.first { $0.id == draft.accountID }?.color : nil
        return Row(
            id: draft.id,
            recipients: recipients.formatted(.list(type: .and, width: .short)),
            subject: draft.subject.isEmpty
                ? String(localized: "No Subject", bundle: .module, comment: "Shown for a message without a subject")
                : draft.subject,
            time: ScheduledTime.text(for: message.sendAt),
            accountColor: color)
    }
}

/// How a scheduled time reads: "Today at 9:00 PM", "Tomorrow at 8:00 AM", then a date.
enum ScheduledTime {
    static func text(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}
