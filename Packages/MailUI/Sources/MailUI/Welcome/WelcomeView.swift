import MailCore
import SwiftUI

/// Shown while no account has been added: what Goodmail is, then a button for each service to sign in to.
struct WelcomeView: View {
    let adder: AccountAdder

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Goodmail", bundle: .module, comment: "The app's name, as the welcome screen's title")
                    .font(Font(Typography.title))
                Text(
                    "Fast, simple mail. Add an account to get started.", bundle: .module,
                    comment: "Welcome screen: what the app is and what to do first"
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                ServiceChooser(adder: adder)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .signInFailureAlert(adder)
    }
}

/// The welcome screen, for UIKit to show.
public enum WelcomeScreen {
    public static func make(adder: AccountAdder) -> UIViewController {
        UIHostingController(rootView: WelcomeView(adder: adder))
    }
}
