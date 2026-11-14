import MailCore
import SwiftUI

/// One account's own settings: the name its mail goes under, its color, its Inbox, and removing it.
struct AccountSettingsView: View {
    let model: SettingsViewModel
    let accountID: AccountID
    @State private var name = ""
    @State private var isConfirmingRemoval = false
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
                    text: $name,
                    prompt: Text("Your Name", bundle: .module, comment: "Placeholder for an account's sender name")
                ) {
                    Text("Name", bundle: .module, comment: "Label of an account's sender name field")
                }
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit { model.rename(accountID, to: name) }
            } header: {
                Text("Name", bundle: .module, comment: "Settings section for an account's sender name")
            } footer: {
                Text(
                    "Shown to the people you write to from \(account.email).", bundle: .module,
                    comment: "Explains an account's sender name")
            }

            Section {
                ColorChoices(selection: account.color) { model.setColor($0, for: accountID) }
            } header: {
                Text("Color", bundle: .module, comment: "Settings section for an account's theme color")
            }

            if account.service.hasInboxCategories {
                Section {
                    Toggle(
                        isOn: Binding(
                            get: { model.sortsInbox(accountID) },
                            set: { model.setSortsInbox($0, for: accountID) })
                    ) {
                        Text("Inbox Categories", bundle: .module, comment: "Setting for Gmail's Inbox categories")
                    }
                } footer: {
                    Text(
                        "Sorts the Inbox into Primary, Promotions, Social, Updates and Forums, as Gmail does.",
                        bundle: .module, comment: "Explains the Inbox Categories setting")
                }
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Text("Remove Account", bundle: .module, comment: "Removes an account from the device")
                }
            }
        }
        .navigationTitle(account.email)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = account.name ?? "" }
        // Leaving without pressing Done keeps what was typed.
        .onDisappear { model.rename(accountID, to: name) }
        .confirmationDialog(
            Text("Remove Account?", bundle: .module, comment: "Asks before removing an account"),
            isPresented: $isConfirmingRemoval, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                dismiss()
                Task { await model.removeAccount(accountID) }
            } label: {
                Text("Remove Account", bundle: .module, comment: "Removes an account from the device")
            }
        } message: {
            Text(
                "\(account.email) and its mail are removed from this device. Nothing is deleted from Gmail.",
                bundle: .module, comment: "Explains what removing an account does")
        }
    }
}
