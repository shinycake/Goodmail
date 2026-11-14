import MailCore
import SwiftUI

/// Accounts, the mail list and sending, as a system form.
struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var removing: Account?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(model.accounts) { account in
                    NavigationLink(value: account.id) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(account.name ?? account.email)
                                if account.name != nil {
                                    Text(account.email).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Circle().fill(Color(account.color.uiColor)).frame(width: 12, height: 12)
                        }
                    }
                    .swipeActions { removeButton(account) }
                    .contextMenu { removeButton(account) }
                }
                NavigationLink {
                    AddAccountView(model: model)
                } label: {
                    Label {
                        Text(
                            "Add Account", tableName: "Settings", bundle: .module, comment: "Adds another mail account")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            } header: {
                Text(
                    "Accounts", tableName: "Settings", bundle: .module, comment: "Settings section listing the accounts"
                )
            }

            Section {
                Picker(selection: $model.rowDisplay.previewLines) {
                    ForEach(RowDisplay.previewLineChoices, id: \.self) { lines in
                        Text(RowDisplay.previewTitle(lines)).tag(lines)
                    }
                } label: {
                    Text(
                        "Preview", tableName: "Settings", bundle: .module,
                        comment: "Setting for how much of each message a mailbox row shows")
                }
                Toggle(isOn: $model.rowDisplay.showsAvatars) {
                    Text(
                        "Avatars", tableName: "Settings", bundle: .module,
                        comment: "Setting for the sender's initials beside each row")
                }
            } header: {
                Text(
                    "Mail List", tableName: "Settings", bundle: .module,
                    comment: "Settings section for how mailbox rows look")
            } footer: {
                Text(
                    "Without avatars, a dot beside a row still marks unread mail.", tableName: "Settings",
                    bundle: .module,
                    comment: "Explains turning avatars off")
            }

            if model.accounts.count > 1 { ThemeSection(model: model) }

            Section {
                Picker(selection: $model.conversationLayout) {
                    ForEach(ConversationLayout.allCases, id: \.self) { layout in
                        Text(layout.title).tag(layout)
                    }
                } label: {
                    Text(
                        "Layout", tableName: "Settings", bundle: .module,
                        comment: "Setting for how a conversation reads")
                }
            } header: {
                Text(
                    "Conversations", tableName: "Settings", bundle: .module,
                    comment: "Settings section for how conversations read")
            } footer: {
                Text(
                    "Chat shows each message's new words as bubbles. Switch one conversation from its toolbar.",
                    tableName: "Settings", bundle: .module, comment: "Explains the conversation layout setting")
            }

            Section {
                Picker(selection: $model.undoSendSeconds) {
                    ForEach(Preferences.undoSendChoices, id: \.self) { seconds in
                        Text(SettingsViewModel.undoSendTitle(seconds)).tag(seconds)
                    }
                } label: {
                    Text(
                        "Undo Send", tableName: "Settings", bundle: .module,
                        comment: "Setting for how long a sent message can be taken back")
                }
            } footer: {
                Text(
                    "How long a sent message waits, so you can take it back.", tableName: "Settings", bundle: .module,
                    comment: "Explains the Undo Send setting")
            }
        }
        .navigationDestination(for: AccountID.self) { AccountSettingsView(model: model, accountID: $0) }
        .navigationTitle(
            Text("Settings", tableName: "Settings", bundle: .module, comment: "Title of the settings screen")
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { dismiss() }
            }
        }
        .confirmationDialog(
            Text("Remove Account?", tableName: "Settings", bundle: .module, comment: "Asks before removing an account"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { account in
            Button(role: .destructive) {
                Task { await model.removeAccount(account.id) }
            } label: {
                Text(
                    "Remove Account", tableName: "Settings", bundle: .module,
                    comment: "Removes an account from the device")
            }
        } message: { account in
            Text(
                "\(account.email) and its mail are removed from this device. Nothing is deleted from Gmail.",
                tableName: "Settings", bundle: .module, comment: "Explains what removing an account does")
        }
        .alert(
            Text(
                "Something Went Wrong", tableName: "Settings", bundle: .module,
                comment: "Title of a settings failure alert"),
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
        ) {
        } message: {
            Text(model.error?.localizedDescription ?? "")
        }
    }
}

extension SettingsView {
    private func removeButton(_ account: Account) -> some View {
        Button(role: .destructive) {
            removing = account
        } label: {
            Label {
                Text(
                    "Remove Account", tableName: "Settings", bundle: .module,
                    comment: "Removes an account from the device")
            } icon: {
                Image(systemName: "minus.circle")
            }
        }
    }
}

/// The settings screen, for UIKit to present.
public enum SettingsScreen {
    public static func make(model: SettingsViewModel) -> UIViewController {
        Controller(model: model)
    }

    private struct Root: View {
        let model: SettingsViewModel

        var body: some View {
            NavigationStack { SettingsView(model: model) }
        }
    }

    /// Tells the model the screen closed only when the screen itself is dismissed. The root view also goes off
    /// screen when an account or Add Account is pushed over it, and treating that as closing rebuilt the mail
    /// screens under the open sheet, which took Settings down with them.
    private final class Controller: UIHostingController<Root> {
        private let model: SettingsViewModel

        init(model: SettingsViewModel) {
            self.model = model
            super.init(rootView: Root(model: model))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed { model.didClose() }
        }
    }
}
