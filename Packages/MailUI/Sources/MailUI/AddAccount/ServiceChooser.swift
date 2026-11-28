import MailCore
import SwiftUI

/// One button per service to sign in to. While one signs in, it shows progress and the others wait.
struct ServiceChooser: View {
    let adder: AccountAdder

    var body: some View {
        ForEach(adder.services, id: \.self) { service in
            Button {
                adder.add(service)
            } label: {
                Label {
                    Text(service.displayName)
                } icon: {
                    if adder.signingIn == service {
                        ProgressView()
                    } else {
                        ServiceLogo(service: service)
                    }
                }
            }
            .disabled(adder.signingIn != nil)
            .accessibilityIdentifier("addAccount.\(service.rawValue)")
        }
    }
}

extension View {
    /// Shows the adder's last failed sign-in.
    func signInFailureAlert(_ adder: AccountAdder) -> some View {
        alert(
            Text(
                "Couldn’t Add Account", tableName: "AddAccount", bundle: .module, comment: "Sign-in failure alert title"
            ),
            isPresented: Binding(get: { adder.failure != nil }, set: { if !$0 { adder.dismissFailure() } })
        ) {
        } message: {
            Text(adder.failure.map(FailureReason.message(for:)) ?? "")
        }
    }
}
