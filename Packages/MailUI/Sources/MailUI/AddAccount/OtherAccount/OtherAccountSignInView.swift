import MailCore
import SwiftUI

/// Why a sign-in to another mail account failed, as the form explains it.
nonisolated public enum OtherAccountSignInFailure: Error, Equatable {
    public enum Server: Sendable, Equatable {
        case incoming, outgoing
    }

    /// The server refused the user name or the password.
    case refused(Server)
    /// The server won't turn on TLS, so the password wasn't sent.
    case insecure(Server)
    /// The server couldn't be reached, or didn't answer as a mail server does.
    case unreachable(Server)
}

/// Signing in to a mail account on any IMAP and SMTP server, as Mail's Other account does: the name, address and
/// password first. Goodmail then looks the servers up and logs in to them; only when it can't find them, or they
/// don't answer, does it ask for them, filled in with what it found or guessed.
struct OtherAccountSignInView: View {
    let discover: (_ email: String) async -> MailServerSettings?
    let guess: (_ email: String) -> MailServerSettings
    let signIn:
        (_ email: String, _ name: String?, _ settings: MailServerSettings, _ password: String) async throws -> Void
    let finished: (_ added: Bool) -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var stage = OtherAccountStage.account(failure: nil)
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, email, password
    }

    var body: some View {
        Form {
            Section {
                TextField(Self.string("Name", "Other account: the name mail is sent under"), text: $name)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .accessibilityIdentifier("other-account-name")
                TextField(Self.string("Email", "Other account: the address field"), text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .accessibilityIdentifier("other-account-email")
                SecureField(Self.string("Password", "Other account: the password field"), text: $password)
                    .textContentType(.password)
                    // Passwords are mostly Latin, so a Hebrew or other keyboard isn't the one it opens with.
                    .keyboardType(.asciiCapable)
                    .focused($focusedField, equals: .password)
                    .accessibilityIdentifier("other-account-password")
            } footer: {
                // Always one Text, so the section keeps its identity between stages and the secure field keeps
                // showing what was typed.
                if stage.foundNoServers {
                    Text(
                        "Goodmail couldn’t find this provider’s servers. Enter them as your provider gives them.",
                        tableName: "OtherAccount", bundle: .module,
                        comment: "Other account: the lookup found no servers for the address")
                } else {
                    Text(
                        "Goodmail looks up your provider’s servers. If your provider asks for an app password, use one here.",
                        tableName: "OtherAccount", bundle: .module,
                        comment: "Other account: what happens with the address and password")
                }
            }
            // Disabling the fields while checking leaves the secure field blank once it's enabled again, so they
            // only stop taking touches.
            .allowsHitTesting(!stage.isBusy)
            if let servers = stage.shownServers {
                ServerSettingsSections(
                    settings: Binding(
                        get: { stage.shownServers ?? servers },
                        set: { stage = stage.editing($0) })
                )
                .allowsHitTesting(!stage.isBusy)
            }
            if let failure = stage.failure {
                Section {
                    Text(Self.message(for: failure)).foregroundStyle(.red)
                }
            }
        }
        .onSubmit { submit() }
        // SwiftUI owns the work: it starts when the stage turns busy and is cancelled if the form goes away.
        .task(id: stage) {
            switch stage {
            case .discovering: await lookUp()
            case .signingIn(let settings), .checking(let settings, _): await signIn(with: settings)
            case .account, .servers: break
            }
        }
        .navigationTitle(Text(verbatim: MailService.imap.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    finished(false)
                } label: {
                    Text(
                        "Cancel", tableName: "OtherAccount", bundle: .module,
                        comment: "Closes the other account sign-in without adding the account")
                }
                .disabled(stage.isBusy)
            }
            ToolbarItem(placement: .confirmationAction) {
                if stage.isBusy {
                    ProgressView()
                } else {
                    Button(action: submit) {
                        if stage.isOnAccount {
                            Text(
                                "Next", tableName: "OtherAccount", bundle: .module,
                                comment: "Looks up the servers for the address and signs in")
                        } else {
                            Text(
                                "Sign In", tableName: "OtherAccount", bundle: .module,
                                comment: "Signs in to the servers as typed")
                        }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("other-account-submit")
                }
            }
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty && stage.submitted != nil
    }

    private func submit() {
        guard canSubmit, let next = stage.submitted else { return }
        stage = next
    }

    private func lookUp() async {
        let found = await discover(email)
        // A form that went away, or moved on, keeps its stage.
        guard !Task.isCancelled else { return }
        stage = .lookedUp(found, guess: guess(email))
    }

    private func signIn(with settings: MailServerSettings) async {
        let typedName = name.trimmingCharacters(in: .whitespaces)
        do {
            try await signIn(email, typedName.isEmpty ? nil : typedName, settings, password)
            finished(true)
        } catch let failure as OtherAccountSignInFailure {
            if case .refused = failure {
                // As Apple's own sign-ins do: the refused password goes, ready to be typed again.
                password = ""
                focusedField = .password
            }
            stage = stage.failed(.signIn(failure))
        } catch is CancellationError {
            return
        } catch {
            stage = stage.failed(.other(error.localizedDescription))
        }
    }

    private static func message(for failure: OtherAccountStage.Failure) -> String {
        switch failure {
        case .signIn(let failure): message(for: failure)
        case .other(let message): message
        }
    }

    private static func message(for failure: OtherAccountSignInFailure) -> String {
        switch failure {
        case .refused(.incoming), .refused(.outgoing):
            string(
                "The server didn’t accept this user name and password.",
                "Other account: the IMAP or SMTP server refused the login")
        case .insecure(.incoming):
            string(
                "The incoming server doesn’t offer a secure connection on this port, so your password wasn’t sent.",
                "Other account: the IMAP server won't use TLS")
        case .insecure(.outgoing):
            string(
                "The outgoing server doesn’t offer a secure connection on this port, so your password wasn’t sent.",
                "Other account: the SMTP server won't use TLS")
        case .unreachable(.incoming):
            string(
                "Couldn’t connect to the incoming server. Check its host name, port and security.",
                "Other account: the IMAP server didn't answer")
        case .unreachable(.outgoing):
            string(
                "Couldn’t connect to the outgoing server. Check its host name, port and security.",
                "Other account: the SMTP server didn't answer")
        }
    }

    static func string(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: key, table: "OtherAccount", bundle: .module, comment: comment)
    }
}

/// The sign-in to another mail account, for UIKit to present over the account chooser.
public enum OtherAccountSignInScreen {
    /// `discover` looks up an address's servers, and `guess` names likely ones to correct when it finds none.
    /// `signIn` logs in and adds the account, throwing `OtherAccountSignInFailure` when a server refuses or doesn't
    /// answer. `finished` is called once, with whether the account was added; the screen can't be swiped away.
    public static func make(
        discover: @escaping (_ email: String) async -> MailServerSettings?,
        guess: @escaping (_ email: String) -> MailServerSettings,
        signIn:
            @escaping (_ email: String, _ name: String?, _ settings: MailServerSettings, _ password: String)
            async throws -> Void,
        finished: @escaping (_ added: Bool) -> Void
    ) -> UIViewController {
        let screen = UIHostingController(
            rootView: NavigationStack {
                OtherAccountSignInView(discover: discover, guess: guess, signIn: signIn, finished: finished)
            })
        screen.isModalInPresentation = true
        return screen
    }
}
