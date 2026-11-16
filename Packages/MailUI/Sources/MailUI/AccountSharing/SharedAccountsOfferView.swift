import MailCore
public import SwiftUI

/// Offers the accounts set up on the reader's other devices: a list to choose from, then Add or Not Now.
struct SharedAccountsOfferView: View {
    @Bindable var offer: SharedAccountsOffer
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 48
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "key.icloud")
                        .font(.system(size: symbolSize))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(
                        "Accounts from Your Other Devices", tableName: "AccountSharing", bundle: .module,
                        comment: "Title of the offer to add accounts set up on the reader's other devices"
                    )
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    Text(
                        "These accounts are already set up on your other devices. Add them here without signing in again.",
                        tableName: "AccountSharing", bundle: .module,
                        comment: "Explains the offer of accounts from the reader's other devices"
                    )
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
                Text(
                    "Their sign-ins are kept in iCloud Keychain, end-to-end encrypted. Adding or removing an account on one device then does the same on the others. You can change this in Settings.",
                    tableName: "AccountSharing", bundle: .module,
                    comment: "Explains where the offered sign-ins come from and what accepting turns on")
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
                        Text(
                            "Add \(offer.chosen.count) Accounts", tableName: "AccountSharing", bundle: .module,
                            comment: "Adds the chosen accounts from the reader's other devices")
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
        UIHostingController(rootView: SharedAccountsOfferView(offer: offer))
    }
}
