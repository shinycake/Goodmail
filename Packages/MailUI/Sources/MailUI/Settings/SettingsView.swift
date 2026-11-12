import MailCore
import SwiftUI

/// Accounts and sending, as a system form.
struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var removing: Account?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(model.accounts) { account in
                    Label {
                        Text(account.email)
                    } icon: {
                        Circle().fill(Color(account.color.uiColor)).frame(width: 12, height: 12)
                    }
                    .swipeActions { removeButton(account) }
                    .contextMenu { removeButton(account) }
                }
                Button {
                    Task { await model.addAccount() }
                } label: {
                    Label {
                        Text("Add Account", bundle: .module, comment: "Signs in to another Gmail account")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .disabled(model.isAddingAccount)
            } header: {
                Text("Accounts", bundle: .module, comment: "Settings section listing the accounts")
            }

            Section {
                ForEach(model.accounts) { account in
                    Toggle(
                        account.email,
                        isOn: Binding(
                            get: { model.sortsInbox(account.id) },
                            set: { model.setSortsInbox($0, for: account.id) }))
                }
            } header: {
                Text("Inbox Categories", bundle: .module, comment: "Settings section for Gmail's Inbox categories")
            } footer: {
                Text(
                    "Sorts the Inbox into Primary, Promotions, Social, Updates and Forums, as Gmail does.",
                    bundle: .module, comment: "Explains the Inbox Categories setting")
            }

            Section {
                Picker(selection: $model.undoSendSeconds) {
                    ForEach(Preferences.undoSendChoices, id: \.self) { seconds in
                        Text(SettingsViewModel.undoSendTitle(seconds)).tag(seconds)
                    }
                } label: {
                    Text("Undo Send", bundle: .module, comment: "Setting for how long a sent message can be taken back")
                }
            } footer: {
                Text(
                    "How long a sent message waits, so you can take it back.", bundle: .module,
                    comment: "Explains the Undo Send setting")
            }
        }
        .onDisappear { model.didClose() }
        .navigationTitle(Text("Settings", bundle: .module, comment: "Title of the settings screen"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { dismiss() }
            }
        }
        .confirmationDialog(
            Text("Remove Account?", bundle: .module, comment: "Asks before removing an account"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { account in
            Button(role: .destructive) {
                Task { await model.removeAccount(account.id) }
            } label: {
                Text("Remove Account", bundle: .module, comment: "Removes an account from the device")
            }
        } message: { account in
            Text(
                "\(account.email) and its mail are removed from this device. Nothing is deleted from Gmail.",
                bundle: .module, comment: "Explains what removing an account does")
        }
        .alert(
            Text("Something Went Wrong", bundle: .module, comment: "Title of a settings failure alert"),
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
                Text("Remove Account", bundle: .module, comment: "Removes an account from the device")
            } icon: {
                Image(systemName: "minus.circle")
            }
        }
    }
}

/// The settings screen, for UIKit to present.
public enum SettingsScreen {
    public static func make(model: SettingsViewModel) -> UIViewController {
        UIHostingController(rootView: NavigationStack { SettingsView(model: model) })
    }
}
