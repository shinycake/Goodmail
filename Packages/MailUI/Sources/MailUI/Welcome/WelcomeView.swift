import MailCore
public import SwiftUI

/// Shown while no account has been added: what Goodmail is, then a button for each service to sign in to.
struct WelcomeView: View {
    let adder: AccountAdder
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 56

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: symbolSize))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(
                    "Goodmail", tableName: "Welcome", bundle: .module,
                    comment: "The app's name, as the welcome screen's title"
                )
                .font(.title2.weight(.semibold))
                Text(
                    "Fast, simple mail. Add an account to get started.", tableName: "Welcome", bundle: .module,
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
