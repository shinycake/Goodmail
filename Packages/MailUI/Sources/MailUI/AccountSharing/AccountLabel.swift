import MailCore
import SwiftUI

/// An account as the account lists show it: its service's logo, its name, and its address under the name.
struct AccountLabel: View {
    let account: Account

    var body: some View {
        Label {
            AccountNames(account: account)
        } icon: {
            ServiceLogo(service: account.service)
        }
    }
}

/// An account's name over its address: what the reader calls it, or else the name its mail goes under. The address
/// alone when it has neither.
struct AccountNames: View {
    let account: Account

    var body: some View {
        let name = account.nickname ?? account.name
        VStack(alignment: .leading) {
            Text(verbatim: name ?? account.email)
            if name != nil {
                Text(verbatim: account.email).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
