import MailCore
public import SwiftUI

/// Offers the accounts set up on the reader's other devices, or on this one before a reinstall: a list to choose
/// from, then Add or Not Now.
struct SharedAccountsOfferView: View {
    @Bindable var offer: SharedAccountsOffer
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 48
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: offer.origin == .thisDevice ? "arrow.counterclockwise.circle" : "key.icloud")
                        .font(.system(size: symbolSize))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    title
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    explanation
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(offer.accounts) { account in
                    Toggle(isOn: chosen(account.id)) { AccountLabel(account: account) }
                }
            } footer: {
                switch offer.origin {
                case .otherDevices:
                    Text(
                        "Their sign-ins are kept in iCloud Keychain, end-to-end encrypted. Adding or removing an account on one device then does the same on the others. You can change this in Settings.",
                        tableName: "AccountSharing", bundle: .module,
                        comment: "Explains where the offered sign-ins come from and what accepting turns on")
                case .thisDevice:
                    Text(
                        "Their sign-ins stayed in this device's Keychain when Goodmail was deleted. Turn off any you don't want back.",
                        tableName: "AccountSharing", bundle: .module,
                        comment: "Explains where the sign-ins of accounts restored after a reinstall come from")
                }
            }
        }
        .disabled(offer.state == .adding)
        .safeAreaBar(edge: .bottom) { buttons }
        .alert(
            Text(
                "Couldn't Add the Accounts", tableName: "AccountSharing", bundle: .module,
                comment: "Title of the alert when adding accounts from other devices failed"),
            isPresented: Binding(get: { offer.error != nil }, set: { if !$0 { offer.error = nil } })
        ) {
        } message: {
            Text(offer.error?.localizedDescription ?? "")
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await offer.addChosen()
                    if offer.error == nil { dismiss() }
                }
            } label: {
                Group {
                    if offer.state == .adding {
                        ProgressView()
                    } else {
                        switch offer.origin {
                        case .otherDevices:
                            Text(
                                "Add \(offer.chosen.count) Accounts", tableName: "AccountSharing", bundle: .module,
                                comment: "Adds the chosen accounts from the reader's other devices")
                        case .thisDevice:
                            Text(
                                "Restore \(offer.chosen.count) Accounts", tableName: "AccountSharing", bundle: .module,
                                comment: "Adds back the chosen accounts this device had before Goodmail was deleted")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(offer.chosen.isEmpty || offer.state == .adding)
            Button {
                offer.notNow()
                dismiss()
            } label: {
                Text(
                    "Not Now", tableName: "AccountSharing", bundle: .module,
                    comment: "Puts off adding the accounts from the reader's other devices"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(offer.state == .adding)
        }
        .controlSize(.large)
        .frame(maxWidth: 360)
        .padding()
    }

    private var title: Text {
        switch offer.origin {
        case .otherDevices:
            Text(
                "Accounts from Your Other Devices", tableName: "AccountSharing", bundle: .module,
                comment: "Title of the offer to add accounts set up on the reader's other devices")
        case .thisDevice:
            Text(
                "Welcome Back", tableName: "AccountSharing", bundle: .module,
                comment: "Title of the offer to restore the accounts this device had before Goodmail was deleted")
        }
    }

    private var explanation: Text {
        switch offer.origin {
        case .otherDevices:
            Text(
                "These accounts are already set up on your other devices. Add them here without signing in again.",
                tableName: "AccountSharing", bundle: .module,
                comment: "Explains the offer of accounts from the reader's other devices")
        case .thisDevice:
            Text(
                "Goodmail still has the accounts you used on this device. Restore them without signing in again.",
                tableName: "AccountSharing", bundle: .module,
                comment: "Explains the offer to restore accounts after Goodmail was deleted and installed again")
        }
    }

    private func chosen(_ id: AccountID) -> Binding<Bool> {
        Binding(
            get: { offer.chosen.contains(id) },
            set: { isOn in
                if isOn { offer.chosen.insert(id) } else { offer.chosen.remove(id) }
            })
    }
}

/// The offer, for UIKit to show: in place of the welcome screen, or as a sheet over the mail.
public enum SharedAccountsOfferScreen {
    public static func make(offer: SharedAccountsOffer) -> UIViewController {
        ArrivalBlockingHost(rootView: SharedAccountsOfferView(offer: offer))
    }
}
