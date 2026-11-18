import MailCore
public import SwiftUI

/// Shown while no account has been added: the app's envelopes and its name, then a button for each service to sign in
/// to.
struct WelcomeView: View {
    let adder: AccountAdder
    /// Scans another device's transfer code; `nil` where accounts can't be transferred.
    let receiveTransfer: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                // A short screen, like an iPhone SE's, tightens up so every button shows without scrolling.
                let isShort = proxy.size.height < 720
                VStack(spacing: isShort ? 20 : 32) {
                    WelcomeHero(isShort: isShort)
                    choices.padding(.horizontal, 24)
                }
                .padding(.bottom, 16)
                // Fills the screen when it fits, so the envelopes' stage takes the height the buttons leave and the
                // buttons sit at the bottom within reach of a thumb; scrolls at the largest text sizes.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The screen has no navigation bar to blur text scrolled under the status bar, so the scrolling stops at
            // the top of the safe area instead of running into the clock. It still runs under the home indicator.
            .mask { Rectangle().ignoresSafeArea(edges: [.horizontal, .bottom]) }
        }
        .background { WelcomeBackdrop() }
        .signInFailureAlert(adder)
    }

    private var choices: some View {
        VStack(spacing: 20) {
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    ServiceChooser(adder: adder)
                        .labelStyle(WelcomeServiceLabelStyle())
                        .buttonStyle(.glass)
                        // A capsule turns into an oval around a label that wraps, at accessibility sizes.
                        .buttonBorderShape(
                            dynamicTypeSize.isAccessibilitySize ? .roundedRectangle(radius: 24) : .capsule
                        )
                        .controlSize(.large)
                }
            }
            if let receiveTransfer {
                Button(action: receiveTransfer) {
                    Label {
                        Text(
                            "Transfer from Another Device", tableName: "Welcome", bundle: .module,
                            comment: "Welcome screen: scans the QR code another device shows to get its accounts"
                        )
                        // Wraps rather than truncates at the largest text sizes.
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                    } icon: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .font(.body.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: 400)
    }
}

/// The welcome screen, for UIKit to show.
public enum WelcomeScreen {
    public static func make(adder: AccountAdder, receiveTransfer: (() -> Void)? = nil) -> UIViewController {
        UIHostingController(rootView: WelcomeView(adder: adder, receiveTransfer: receiveTransfer))
    }
}
