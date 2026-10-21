#if DEBUG
    import Foundation
    import GmailProvider
    import MailCore

    /// Launch with `-GoodmailDeliverTestMessageAfter 20` to have a message appear in the first account's Inbox
    /// that many seconds later. It is inserted with `messages.insert`, which files a message in the user's own
    /// mailbox without sending anything, so live sync can be shown on demand.
    enum TestDelivery {
        static func scheduleIfRequested(model: AppModel) {
            let delay = UserDefaults.standard.integer(forKey: "GoodmailDeliverTestMessageAfter")
            guard delay > 0, let account = model.accounts.first else { return }
            Task {
                do {
                    try await Task.sleep(for: .seconds(delay))
                    try await insert(into: account)
                } catch {
                    print("Test delivery failed: \(error)")
                }
            }
        }

        private static func insert(into account: Account) async throws {
            let date = Date.now.formatted(.iso8601)
            let message = """
                From: =?UTF-8?B?\(Data("יעל כהן".utf8).base64EncodedString())?= <yael@example.co.il>
                To: \(account.email)
                Subject: =?UTF-8?B?\(Data("נחת עכשיו — test delivery".utf8).base64EncodedString())?=
                Date: \(Date.now.formatted(.dateTime.locale(Locale(identifier: "en_US_POSIX"))))
                Content-Type: text/plain; charset=UTF-8

                Inserted by Goodmail's test delivery at \(date).
                """
                .replacingOccurrences(of: "\n", with: "\r\n")
            _ = try await DebugGmail(session: GmailSession(accountID: account.id))
                .insert(raw: Data(message.utf8), datedByHeader: false)
        }
    }
#endif
