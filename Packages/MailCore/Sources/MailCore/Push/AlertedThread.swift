/// How a new-mail alert names its thread in its `userInfo`, read by the iPhone app and by the Apple Watch app, which
/// opens the thread when the reader taps the alert mirrored to the wrist.
public enum AlertedThread {
    static let accountKey = "accountID"
    static let threadKey = "threadID"

    /// What an alert about `thread` carries.
    public static func userInfo(for thread: ThreadSummary.ID) -> [String: String] {
        [accountKey: thread.accountID.rawValue, threadKey: thread.threadID]
    }

    /// The thread an alert is about, or `nil` for one that isn't about a thread, such as the bare push shown when
    /// the extension couldn't fetch.
    public static func thread(in userInfo: [AnyHashable: Any]) -> ThreadSummary.ID? {
        guard let account = userInfo[accountKey] as? String, let thread = userInfo[threadKey] as? String else {
            return nil
        }
        return ThreadSummary.ID(accountID: AccountID(rawValue: account), threadID: thread)
    }
}
