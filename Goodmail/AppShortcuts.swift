// The shortcuts use MailIntents, which the Linux cloud build can't build (docs/setup/cloud-builds.md).
#if canImport(MailIntents)
    import AppIntents
    import MailIntents

    /// The phrases Siri and Spotlight offer without setup, in English and Hebrew (AppShortcuts.xcstrings).
    struct GoodmailShortcuts: AppShortcutsProvider {
        static var appShortcuts: [AppShortcut] {
            AppShortcut(
                intent: NewMessageIntent(),
                phrases: [
                    "New message in \(.applicationName)",
                    "Write an email in \(.applicationName)",
                    "New \(.applicationName) message from \(\.$account)",
                ],
                shortTitle: "New Message",
                systemImageName: "square.and.pencil")
            AppShortcut(
                intent: OpenInboxIntent(),
                phrases: ["Open my \(.applicationName) inbox", "Check \(.applicationName)"],
                shortTitle: "Inbox",
                systemImageName: "tray")
            AppShortcut(
                intent: OpenMailboxIntent(),
                phrases: ["Open \(\.$target) in \(.applicationName)", "Show \(\.$target) in \(.applicationName)"],
                shortTitle: "Open Mailbox",
                systemImageName: "folder")
        }
    }
#endif
