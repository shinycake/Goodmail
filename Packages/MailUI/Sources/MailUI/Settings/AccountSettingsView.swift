import MailCore
import SwiftUI
import UIKit

/// One account's own settings: what the app calls it, the name its mail goes under, its color, its signature, its Inbox, and removing it.
struct AccountSettingsView: View {
    let model: SettingsViewModel
    let accountID: AccountID
    @State private var name = ""
    @State private var nickname = ""
    @State private var removing: Account?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let account = model.accounts.first(where: { $0.id == accountID }) {
            form(for: account)
        }
    }

    private func form(for account: Account) -> some View {
        Form {
            Section {
                TextField(
                    text: $nickname,
                    prompt: Text(verbatim: account.email)
                ) {
                    Text(
                        "Description", tableName: "Settings", bundle: .module,
                        comment: "Names an account in the app, such as Work or Personal, as Apple Mail calls it")
                }
                .submitLabel(.done)
                .onSubmit { model.setNickname(accountID, to: nickname) }
            } header: {
                Text(
                    "Description", tableName: "Settings", bundle: .module,
                    comment: "Names an account in the app, such as Work or Personal, as Apple Mail calls it")
            } footer: {
                Text(
                    "A name for this account, like Work or Personal, shown instead of its address. Only you see it.",
                    tableName: "Settings", bundle: .module, comment: "Explains an account's description")
            }

            Section {
                TextField(
                    text: $name,
                    prompt: Text(
                        "Your Name", tableName: "Settings", bundle: .module,
                        comment: "Placeholder for an account's sender name")
                ) {
                    Text(
                        "Name", tableName: "Settings", bundle: .module,
                        comment: "Label of an account's sender name field")
                }
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit { model.rename(accountID, to: name) }
            } header: {
                Text(
                    "Name", tableName: "Settings", bundle: .module,
                    comment: "Settings section for an account's sender name")
            } footer: {
                Text(
                    "Shown to the people you write to from \(account.email).", tableName: "Settings", bundle: .module,
                    comment: "Explains an account's sender name")
            }

            Section {
                ColorChoices(selection: account.color) { model.setColor($0, for: accountID) }
            } header: {
                Text(
                    "Color", tableName: "Settings", bundle: .module,
                    comment: "Settings section for an account's theme color")
            }

            Section {
                SignatureRow(signatures: model.signatures, account: account)
            }

            if account.service.hasInboxCategories {
                Section {
                    Toggle(
                        isOn: Binding(
                            get: { model.sortsInbox(accountID) },
                            set: { model.setSortsInbox($0, for: accountID) })
                    ) {
                        Text(
                            "Inbox Categories", tableName: "Settings", bundle: .module,
                            comment: "Setting for Gmail's Inbox categories")
                    }
                } footer: {
                    Text(
                        "Sorts the Inbox into Primary, Promotions, Social, Updates and Forums, as Gmail does.",
                        tableName: "Settings", bundle: .module, comment: "Explains the Inbox Categories setting")
                }
            }

            if let servers = model.serverSettings(accountID) {
                Section {
                    NavigationLink {
                        ServerSettingsView(service: servers)
                    } label: {
                        ServerSettingsView.title(servers.kind)
                    }
                }
            }

            if let autoReply = model.autoReply(accountID) {
                Section {
                    NavigationLink {
                        AutoReplyView(service: autoReply)
                    } label: {
                        AutoReplyView.title
                    }
                }
            }

            if let notifications = model.notifications {
                NotificationsSection(choices: notifications, account: account)
            }

            if let badges = model.badges {
                BadgeSection(choices: badges, account: account, sorted: model.sortsInbox(accountID))
            }

            Section {
                Button(role: .destructive) {
                    removing = account
                } label: {
                    Text(
                        "Remove Account", tableName: "Settings", bundle: .module,
                        comment: "Removes an account from the device")
                }
            }
        }
        .navigationTitle(account.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = account.name ?? ""
            nickname = account.nickname ?? ""
        }
        // Leaving without pressing Done keeps what was typed.
        .onDisappear {
            model.setNickname(accountID, to: nickname)
            model.rename(accountID, to: name)
        }
        .removeAccountConfirmation($removing, model: model) { dismiss() }
    }
}

/// Which of the account's new mail alerts, as a checked list. When the reader turned alerts off in iOS Settings, it
/// says so and links there, since only they can turn them back on.
private struct NotificationsSection: View {
    let choices: NotificationChoices
    let account: Account
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if let level = choices.choice(for: account.id) {
                Picker(selection: Binding(get: { level }, set: { choices.set($0, for: account.id) })) {
                    ForEach(NotificationChoices.levels(for: account.service), id: \.self) { level in
                        Text(NotificationChoices.title(level)).tag(level)
                    }
                } label: {
                    Text(
                        "Alert Me About", tableName: "Settings", bundle: .module,
                        comment: "Label of an account's alert choice")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            if choices.isTurnedOffInSettings,
                let settings = URL(string: UIApplication.openNotificationSettingsURLString)
            {
                Button {
                    openURL(settings)
                } label: {
                    Text(
                        "Turn On in Settings", tableName: "Settings", bundle: .module,
                        comment: "Opens iOS Settings to allow alerts")
                }
            }
        } header: {
            Text(
                "Notifications", tableName: "Settings", bundle: .module,
                comment: "Settings section for an account's alerts")
        } footer: {
            // Nothing until iOS has answered, so the footer doesn't change its words under the reader.
            switch choices.status {
            case .loading:
                EmptyView()
            case .loaded(_, turnedOff: true):
                Text(
                    "Notifications for Goodmail are turned off in Settings.", tableName: "Settings", bundle: .module,
                    comment: "Explains why no alerts arrive")
            case .loaded(_, turnedOff: false) where account.service.hasInboxCategories:
                Text(
                    "Primary Only skips Promotions, Social, Updates and Forums.", tableName: "Settings",
                    bundle: .module,
                    comment: "Explains the Primary Only alert choice")
            case .loaded:
                EmptyView()
            }
        }
        .loads(choices)
    }
}
