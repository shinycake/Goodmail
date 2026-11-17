/// Who runs a command: the iPhone, or the watch at the account's service (ADR-023). Stamped once, when the command is
/// made, so a command never changes hands on its way.
public enum WristExecutor: String, Codable, Equatable, Sendable {
    case phone
    case watch

    /// Who runs `kind` for an account with `source`. Pins and snoozes live only in the iPhone's database, so they always
    /// run there.
    public static func `for`(kind: WristCommand.Kind, source: WristAccountSource) -> WristExecutor {
        switch kind {
        case .pin, .snooze, .unsnooze: .phone
        case .archive, .moveToInbox, .trash, .untrash, .markRead, .reply: source == .direct ? .watch : .phone
        }
    }
}
