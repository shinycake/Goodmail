import MailCore
import SwiftUI

/// One button per service to sign in to. While one signs in, it shows progress and the others wait.
struct ServiceChooser: View {
    let adder: AccountAdder

    var body: some View {
        ForEach(adder.services, id: \.self) { service in
            Button {
                Task { await adder.add(service) }
            } label: {
                Label {
                    Text(service.displayName)
                } icon: {
                    if adder.state == .signingIn(service) {
                        ProgressView()
                    } else {
                        Image(systemName: service.symbol)
                    }
                }
            }
            .disabled(adder.state != .choosing)
            .accessibilityIdentifier("addAccount.\(service.rawValue)")
        }
    }
}

extension View {
    /// Shows the adder's last failed sign-in.
    func signInFailureAlert(_ adder: AccountAdder) -> some View {
        alert(
            Text("Couldn’t Add Account", bundle: .module, comment: "Sign-in failure alert title"),
            isPresented: Binding(get: { adder.error != nil }, set: { if !$0 { adder.error = nil } })
        ) {
        } message: {
            Text(adder.error?.localizedDescription ?? "")
        }
    }
}
