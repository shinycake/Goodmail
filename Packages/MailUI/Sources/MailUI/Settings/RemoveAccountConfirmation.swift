import MailCore
import SwiftUI

extension View {
    /// Asks before removing `account` from the device, naming the service that keeps its mail. Confirming runs
    /// `removed` (which may leave the screen) and then has `model` remove the account.
    func removeAccountConfirmation(
        _ account: Binding<Account?>, model: SettingsViewModel, removed: @escaping () -> Void = {}
    ) -> some View {
        confirmationDialog(
            Text("Remove Account?", tableName: "Settings", bundle: .module, comment: "Asks before removing an account"),
            isPresented: Binding(get: { account.wrappedValue != nil }, set: { if !$0 { account.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: account.wrappedValue
        ) { account in
            Button(role: .destructive) {
                removed()
                model.removeAccount(account.id)
            } label: {
                Text(
                    "Remove Account", tableName: "Settings", bundle: .module,
                    comment: "Removes an account from the device")
            }
        } message: { account in
            RemovalExplanation(account: account)
        }
    }
}

/// What removing an account does: its mail leaves this device, and stays with the service that keeps it.
private struct RemovalExplanation: View {
    let account: Account

    var body: some View {
        switch account.service {
        case .gmail:
            Text(
                "\(account.email) and its mail are removed from this device. Nothing is deleted from Gmail.",
                tableName: "Settings", bundle: .module, comment: "Explains what removing a Gmail account does")
        case .outlook:
            Text(
                "\(account.email) and its mail are removed from this device. Nothing is deleted from Outlook.",
                tableName: "Settings", bundle: .module, comment: "Explains what removing an Outlook account does")
        case .icloud:
            Text(
                "\(account.email) and its mail are removed from this device. Nothing is deleted from iCloud.",
                tableName: "Settings", bundle: .module, comment: "Explains what removing an iCloud account does")
        case .imap:
            Text(
                "\(account.email) and its mail are removed from this device. Nothing is deleted from its mail server.",
                tableName: "Settings", bundle: .module,
                comment: "Explains what removing an account on another mail server does")
        }
    }
}
