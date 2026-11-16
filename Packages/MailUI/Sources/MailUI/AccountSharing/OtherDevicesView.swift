import MailCore
import SwiftUI

/// Whether this device syncs its accounts with the reader's other devices, and which accounts are on it: one switch
/// for each of this device's accounts and each one only the other devices have.
struct OtherDevicesView: View {
    @Bindable var model: SettingsViewModel
    let sharing: AccountSharingChoices
    @State private var removing: Account?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { sharing.syncs }, set: { on in Task { await sharing.setSyncs(on) } })) {
                    Text(
                        "Sync Accounts", tableName: "AccountSharing", bundle: .module,
                        comment: "Setting for syncing accounts with the reader's other devices")
                }
                .disabled(sharing.state != .idle)
            } footer: {
                if sharing.syncs {
                    Text(
                        "Your accounts and their sign-ins are kept in iCloud Keychain, end-to-end encrypted. Adding or removing an account on one device does the same on your others.",
                        tableName: "AccountSharing", bundle: .module, comment: "Explains syncing accounts, when it's on"
                    )
                } else {
                    Text(
                        "Accounts stay on this device and aren't shared with your other devices.",
                        tableName: "AccountSharing", bundle: .module,
                        comment: "Explains syncing accounts, when it's off"
                    )
                }
            }

            if sharing.syncs {
                Section {
                    ForEach(model.accounts) { account in
                        Toggle(isOn: Binding(get: { true }, set: { if !$0 { removing = account } })) {
                            AccountLabel(account: account)
                        }
                    }
                    ForEach(sharing.elsewhere) { account in
                        Toggle(
                            isOn: Binding(
                                get: { sharing.state == .adding(account.id) },
                                set: { if $0 { Task { await sharing.add(account.id) } } })
                        ) {
                            AccountLabel(account: account)
                        }
                        .disabled(sharing.state != .idle)
                    }
                } header: {
                    Text(
                        "On This Device", tableName: "AccountSharing", bundle: .module,
                        comment: "Header of the list of accounts, each with a switch for whether it's on this device")
                } footer: {
                    Text(
                        "Turning an account off removes it and its mail from this device only. Your other devices keep it.",
                        tableName: "AccountSharing", bundle: .module,
                        comment: "Explains turning an account off in the list of accounts on this device")
                }
            }

            if let transfer = model.transfer { TransferSection(transfer: transfer) }
        }
        .navigationTitle(OtherDevicesView.title)
        .confirmationDialog(
            Text(
                "Remove from This Device?", tableName: "AccountSharing", bundle: .module,
                comment: "Asks before removing an account from this device only"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { account in
            Button(role: .destructive) {
                model.removeAccount(account.id, .thisDevice)
            } label: {
                Text(
                    "Remove from This Device", tableName: "AccountSharing", bundle: .module,
                    comment: "Removes an account from this device only")
            }
        } message: { account in
            Text(
                "\(account.email) and its mail are removed from this device. Your other devices keep it, and you can turn it back on here.",
                tableName: "AccountSharing", bundle: .module,
                comment: "Explains removing an account from this device only")
        }
        .alert(
            Text(
                "Something Went Wrong", tableName: "AccountSharing", bundle: .module,
                comment: "Title of an alert when a change to syncing accounts failed"),
            isPresented: Binding(get: { sharing.error != nil }, set: { if !$0 { sharing.error = nil } })
        ) {
        } message: {
            Text(sharing.error?.localizedDescription ?? "")
        }
    }

    static var title: Text {
        Text(
            "Other Devices", tableName: "AccountSharing", bundle: .module,
            comment: "Title of the settings page for syncing accounts with the reader's other devices")
    }
}

/// The Settings row that opens Other Devices, saying whether syncing is on.
struct OtherDevicesRow: View {
    @Bindable var model: SettingsViewModel
    let sharing: AccountSharingChoices

    var body: some View {
        NavigationLink {
            OtherDevicesView(model: model, sharing: sharing)
        } label: {
            LabeledContent {
                if sharing.syncs {
                    Text(
                        "On", tableName: "AccountSharing", bundle: .module,
                        comment: "Syncing accounts with other devices is on")
                } else {
                    Text(
                        "Off", tableName: "AccountSharing", bundle: .module,
                        comment: "Syncing accounts with other devices is off")
                }
            } label: {
                Label {
                    OtherDevicesView.title
                } icon: {
                    Image(systemName: "key.icloud")
                }
            }
        }
    }
}
