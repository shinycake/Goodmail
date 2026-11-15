#if DEBUG
    import Foundation
    import MailCore
    import MailNotifications
    import UIKit
    import UserNotifications

    /// Launch with `-GoodmailTestAlertFrom "PayPal <service@paypal.com>"` to get a new-mail alert from that sender
    /// ten seconds later, built as a pushed one is, so its picture and subject can be checked on a simulator, where
    /// no push arrives. `-GoodmailTestAlertSubject` sets the subject.
    enum TestAlert {
        static func scheduleIfRequested(model: AppModel) {
            let defaults = UserDefaults.standard
            guard let from = defaults.string(forKey: "GoodmailTestAlertFrom"), let account = model.accounts.first
            else { return }
            let subject = defaults.string(forKey: "GoodmailTestAlertSubject") ?? "Your October statement is ready"
            // Keeps running after the tester goes to the Home screen, where the banner shows.
            let background = UIApplication.shared.beginBackgroundTask(withName: "Test alert")
            Task { @concurrent in
                do {
                    try await post(from: Contact(parsing: from), subject: subject, in: account)
                } catch {
                    print("Test alert failed: \(error)")
                }
                await MainActor.run { UIApplication.shared.endBackgroundTask(background) }
            }
        }

        private static func post(from sender: Contact, subject: String, in account: Account) async throws {
            let center = UNUserNotificationCenter.current()
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            try await Task.sleep(for: .seconds(10))
            let thread = ThreadSummary(
                id: ThreadSummary.ID(accountID: account.id, threadID: "test-alert-\(UUID().uuidString)"),
                subject: subject, snippet: "A test alert from Goodmail, built the way a pushed one is.",
                sender: sender, date: .now, isUnread: true, messageCount: 1, labelIDs: ["INBOX"])
            let logos = SharedContainer.directoryURL.map {
                SenderLogos(directory: $0.appending(path: "SenderPictures"))
            }
            let picture = await logos?.logo(for: sender.address)
            let mail = NewMail(thread: thread)
            let content = await CommunicationAlert.content(for: mail, in: account, picture: picture)
            try await center.add(
                UNNotificationRequest(
                    identifier: NewMailAlert.identifier(for: thread.id), content: content, trigger: nil))
        }
    }
#endif
