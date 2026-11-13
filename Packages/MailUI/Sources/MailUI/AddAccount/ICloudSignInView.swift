import MailCore
import SwiftUI

/// Why an iCloud sign-in failed, as the form explains it.
public enum ICloudSignInFailure: Error {
    /// iCloud refused the address or the password, most often because it was the Apple Account password.
    case wrongPassword
}

/// iCloud's sign-in: the address and an app-specific password, which iCloud Mail asks other apps for instead of the
/// Apple Account password.
struct ICloudSignInView: View {
    /// Where the form stands. Only `editing` takes input; a failure stays shown until the next try.
    enum Stage: Equatable {
        case editing(failure: String?)
        case checking
    }

    let signIn: (_ email: String, _ appPassword: String) async throws -> Void
    let finished: (_ added: Bool) -> Void

    @State private var email = ""
    @State private var appPassword = ""
    @State private var stage = Stage.editing(failure: nil)

    private static let appPasswords = URL(string: "https://account.apple.com/account/manage/section/security")!

    var body: some View {
        Form {
            Section {
                TextField(
                    String(localized: "iCloud Address", bundle: .module, comment: "iCloud sign-in: the address field"),
                    text: $email
                )
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                SecureField(
                    String(
                        localized: "App-Specific Password", bundle: .module,
                        comment: "iCloud sign-in: the password field"),
                    text: $appPassword
                )
                .textContentType(.password)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "iCloud Mail needs an app-specific password, not your Apple Account password. Make one under Sign-In and Security.",
                        bundle: .module, comment: "iCloud sign-in: why and where to make an app-specific password")
                    Link(destination: Self.appPasswords) {
                        Text("Open account.apple.com", bundle: .module, comment: "iCloud sign-in: opens Apple's site")
                    }
                }
            }
            if case .editing(let failure?) = stage {
                Section {
                    Text(failure).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(Text(verbatim: MailService.icloud.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(stage == .checking)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    finished(false)
                } label: {
                    Text("Cancel", bundle: .module, comment: "Closes the iCloud sign-in without adding the account")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if stage == .checking {
                    ProgressView()
                } else {
                    Button {
                        Task { await submit() }
                    } label: {
                        Text("Sign In", bundle: .module, comment: "Checks the iCloud address and password")
                    }
                    .disabled(email.isEmpty || appPassword.isEmpty)
                }
            }
        }
    }

    private func submit() async {
        stage = .checking
        do {
            try await signIn(email, appPassword)
            finished(true)
        } catch ICloudSignInFailure.wrongPassword {
            stage = .editing(
                failure: String(
                    localized:
                        "iCloud didn’t accept this address and password. Check that it’s an app-specific password, not your Apple Account password.",
                    bundle: .module, comment: "iCloud sign-in: the address or password was refused"))
        } catch {
            stage = .editing(failure: error.localizedDescription)
        }
    }
}

/// The iCloud sign-in, for UIKit to present over the account chooser.
public enum ICloudSignInScreen {
    /// `signIn` checks the address and password and adds the account, throwing `ICloudSignInFailure.wrongPassword`
    /// when iCloud refuses them. `finished` is called once, with whether the account was added; the screen can't be
    /// swiped away, so the reader ends it with Cancel or Sign In.
    public static func make(
        signIn: @escaping (_ email: String, _ appPassword: String) async throws -> Void,
        finished: @escaping (_ added: Bool) -> Void
    ) -> UIViewController {
        let screen = UIHostingController(
            rootView: NavigationStack { ICloudSignInView(signIn: signIn, finished: finished) })
        screen.isModalInPresentation = true
        return screen
    }
}
