#if DEBUG
    import Foundation
    import MailCore
    import MailNotifications
    import UIKit
    import UserNotifications

    /// Launch with `-GoodmailTestAlertFrom "PayPal <service@paypal.com>"` to get a new-mail alert from that sender
    /// ten seconds later, built as a pushed one is, so its picture and subject can be checked on a simulator, where
    /// no push arrives. `-GoodmailTestAlertSubject` sets the subject. `-GoodmailTestAlertThread synthetic-1/t19` makes
    /// it an alert for that conversation, so tapping it opens it as a pushed alert's tap does, through
    /// `AlertResponder` and `PushCoordinator`; it then comes each time a UI test posts `TestTrigger.alert`, two
    /// seconds later, for the test to go to the Home Screen meanwhile and tap its banner there.
    enum TestAlert {
        static func scheduleIfRequested(model: AppModel) {
            let defaults = UserDefaults.standard
            guard let from = defaults.string(forKey: "GoodmailTestAlertFrom"), let account = model.accounts.first
            else { return }
            let subject = defaults.string(forKey: "GoodmailTestAlertSubject") ?? "Your October statement is ready"
            let directory = (SharedContainer.directoryURL ?? URL.cachesDirectory).appending(path: "SenderPictures")
            let pictures = SenderPictureSources(directory: directory, database: model.database)
            let sender = Contact(parsing: from)
            guard
                let thread = defaults.string(forKey: "GoodmailTestAlertThread").flatMap(
                    ThreadSummary.ID.init(testName:))
            else {
                return send(after: .seconds(10)) {
                    try await post(from: sender, subject: subject, in: account, thread: nil, pictures: pictures)
                }
            }
            TestTrigger.alert.onPost {
                send(after: .seconds(2)) {
                    try await post(from: sender, subject: subject, in: account, thread: thread, pictures: pictures)
                }
            }
        }

        /// Runs `posting` `delay` from now, off the main actor. A debug launch option: nothing awaits or cancels it,
        /// and it ends once it has posted, in a background task, as it keeps running after the tester goes to the
        /// Home Screen, where the banner shows.
        private static func send(
            after delay: Duration, _ posting: @escaping @Sendable () async throws -> Void
        ) {
            let background = UIApplication.shared.beginBackgroundTask(withName: "Test alert")
            Task { @concurrent in
                do {
                    try await Task.sleep(for: delay)
                    try await posting()
                } catch {
                    print("Test alert failed: \(error)")
                }
                await MainActor.run { UIApplication.shared.endBackgroundTask(background) }
            }
        }

        private static func post(
            from sender: Contact, subject: String, in account: Account, thread id: ThreadSummary.ID?,
            pictures: SenderPictureSources
        )
            async throws
        {
            let center = UNUserNotificationCenter.current()
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            let thread = ThreadSummary(
                id: id ?? ThreadSummary.ID(accountID: account.id, threadID: "test-alert-\(UUID().uuidString)"),
                subject: subject, snippet: "A test alert from Goodmail, built the way a pushed one is.",
                sender: sender, date: .now, isUnread: true, messageCount: 1, labelIDs: ["INBOX"])
            let picture = await pictures.picture(for: sender.address)
            let mail = NewMail(thread: thread)
            let content = await CommunicationAlert.content(for: mail, in: account, picture: picture)
            try await center.add(
                UNNotificationRequest(
                    identifier: NewMailAlert.identifier(for: thread.id), content: content, trigger: nil))
        }
    }
#endif
