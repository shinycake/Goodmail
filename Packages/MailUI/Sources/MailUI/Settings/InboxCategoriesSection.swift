import MailCore
import SwiftUI

/// One switch for Gmail's Inbox categories across every account that has them. With some accounts on and some off,
/// it shows as mixed; each account's own settings still choose for that account alone.
struct InboxCategoriesSection: View {
    let model: SettingsViewModel
    let accounts: [Account]

    var body: some View {
        Section {
            Toggle(sources: accounts.map(sortsInbox), isOn: \.self) {
                Text(
                    "Inbox Categories", tableName: "Settings", bundle: .module,
                    comment: "Setting for Gmail's Inbox categories")
            }
        } footer: {
            Text(
                "Sorts the Inbox into Primary, Promotions, Social, Updates and Forums, as Gmail does. Each account can also choose in its own settings.",
                tableName: "Settings", bundle: .module,
                comment: "Explains the Inbox Categories setting that covers every Gmail account")
        }
    }

    private func sortsInbox(_ account: Account) -> Binding<Bool> {
        Binding(
            get: { model.sortsInbox(account.id) },
            set: { model.setSortsInbox($0, for: account.id) })
    }
}
