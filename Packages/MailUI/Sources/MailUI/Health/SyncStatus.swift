public import Foundation
import MailCore

/// What the sidebar's footer says about mail coming in on a desktop window: an account's problem first, since it needs
/// the reader, then a check under way, then when mail last came in. Nothing before the first sync.
enum SyncStatus: Equatable {
    case problem(AccountProblemNotice)
    case checking
    case updated(Date)
    case quiet

    init(_ board: AccountHealthBoard, accounts: [Account]) {
        self =
            if let notice = board.notices(for: accounts).first {
                .problem(notice)
            } else if board.syncsUnderWay > 0 {
                .checking
            } else if let date = board.lastUpdated {
                .updated(date)
            } else {
                .quiet
            }
    }

    /// The line as it reads at `now`.
    func text(now: Date) -> String? {
        switch self {
        case .problem(let notice):
            String(
                localized: "\(notice.account.email): \(notice.title)", table: "Health", bundle: .module,
                comment: "Sidebar footer: an account's address and its sync problem, as Sign-In Needed")
        case .checking:
            String(
                localized: "Checking for mail…", table: "Health", bundle: .module,
                comment: "Sidebar footer: a sync is under way")
        case .updated(let date) where now.timeIntervalSince(date) < 60:
            String(
                localized: "Updated just now", table: "Health", bundle: .module,
                comment: "Sidebar footer: mail came in less than a minute ago")
        case .updated(let date):
            String(
                localized: "Updated \(Self.ago.localizedString(for: date, relativeTo: now))",
                table: "Health", bundle: .module,
                comment: "Sidebar footer: when mail last came in, as 'Updated 5 minutes ago'")
        case .quiet: nil
        }
    }

    /// "5 minutes ago", as the system says it in the reader's language.
    private static var ago: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }
}
