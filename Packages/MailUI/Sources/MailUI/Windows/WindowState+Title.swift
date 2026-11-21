import Foundation
public import MailCore

extension WindowState {
    /// What the system calls the window, in the app switcher and wherever it lists the app's windows, so windows read
    /// apart: the open thread's subject, else the list's name, or Mailboxes for a narrow window back at them.
    /// `subject` is the open thread's subject, or `nil` when it isn't here; `labels` name a label's list, and
    /// `smartMailbox` a smart mailbox's.
    public func windowTitle(
        subject: String?, labels: [MailboxDirectory.Label], accounts: [Account], smartMailbox: SmartMailbox? = nil
    ) -> String {
        if openThread != nil, let subject {
            return subject.isEmpty ? ThreadRowMetrics.noSubject : subject
        }
        if depth == .mailboxes { return MailboxesViewController.title }
        return switch list {
        case .mailbox(let mailbox, _): mailbox.listTitle(labels: labels, accounts: accounts)
        case .scheduled:
            String(
                localized: "Scheduled", table: "Mailboxes", bundle: .module,
                comment: "Mailbox: messages waiting to be sent later")
        case .snoozed:
            String(
                localized: "Snoozed", table: "Mailboxes", bundle: .module,
                comment: "Mailbox: threads snoozed until later")
        case .smart: smartMailbox?.title ?? SmartMailbox.sectionTitle
        }
    }
}
