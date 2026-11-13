import MailCore
import SwiftUI

/// Settings' Add Account: the services to sign in to. Goes back to Settings once an account is added.
struct AddAccountView: View {
    let model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ServiceChooser(adder: model.adder)
            } footer: {
                Text(
                    "Goodmail keeps your mail on this device and talks to your provider directly.", bundle: .module,
                    comment: "Add Account: where mail is kept")
            }
        }
        .navigationTitle(Text("Add Account", bundle: .module, comment: "Adds another mail account"))
        .onChange(of: model.accounts) { dismiss() }
        .signInFailureAlert(model.adder)
    }
}
