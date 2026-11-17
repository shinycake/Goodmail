import MailCore
import Testing

/// An alert names its thread the same way for the iPhone and the watch.
struct AlertedThreadTests {
    @Test func readsBackTheThreadItNames() {
        let thread = ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")
        #expect(AlertedThread.thread(in: AlertedThread.userInfo(for: thread)) == thread)
    }

    @Test func aBarePushNamesNoThread() {
        #expect(AlertedThread.thread(in: ["account": "me@example.com", "historyId": "9"]) == nil)
    }
}
