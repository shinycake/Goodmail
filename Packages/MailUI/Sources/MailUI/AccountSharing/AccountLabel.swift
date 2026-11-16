import MailCore
import SwiftUI

/// An account as the account lists show it: its service's logo, its name, and its address under the name.
struct AccountLabel: View {
    let account: Account

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(account.name ?? account.email)
                if account.name != nil {
                    Text(account.email).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } icon: {
            ServiceLogo(service: account.service)
        }
    }
}
