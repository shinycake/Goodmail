public import Foundation
public import MailCore

/// The actions on an alert the relay sent the watch itself (ADR-023), as the watch runs them: only for an account it
/// reads itself, since a relayed account's change needs the iPhone, which didn't answer.
public enum WristAlertAction: String, CaseIterable, Sendable {
    // The same identifiers as the iPhone's alert actions (NewMailAlert.Action).
    case reply, markRead, archive, trash

    /// The command `self` makes for the alert's `target`, with `text` for a reply; `nil` for an alert that opens the
    /// Inbox, an empty reply, or an account the watch doesn't read itself.
    public func command(
        on target: WristAlertTarget, text: String? = nil, sources: [AccountID: WristAccountSource], now: Date
    ) -> WristCommand? {
        guard case .thread(let thread) = target, sources[thread.accountID] == .direct, let kind = kind(text) else {
            return nil
        }
        return WristCommand(threads: [thread], kind: kind, madeAt: now, executor: .watch)
    }

    private func kind(_ text: String?) -> WristCommand.Kind? {
        switch self {
        case .reply:
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return .reply(text)
        case .markRead: return .markRead(true)
        case .archive: return .archive
        case .trash: return .trash
        }
    }
}
