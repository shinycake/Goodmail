import MailCore
import SwiftUI

/// Why a sign-in to another mail account failed, as the form explains it.
public enum OtherAccountSignInFailure: Error, Equatable {
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
    /// Where the form stands. `account` and `servers` take input; a failure stays shown until the next try.
    enum Stage: Equatable {
        /// The name, address and password.
        case account(failure: String?)
        /// Looking the servers up, then logging in to them.
        case discovering
        /// The servers, to fill in or correct. `found` says whether they came from the lookup.
        case servers(found: Bool, failure: String?)
        /// Logging in to the servers as typed.
        case checking

        var isBusy: Bool { self == .discovering || self == .checking }
    }

    let discover: (_ email: String) async -> MailServerSettings?
    let guess: (_ email: String) -> MailServerSettings
    let signIn:
        (_ email: String, _ name: String?, _ settings: MailServerSettings, _ password: String) async throws -> Void
    let finished: (_ added: Bool) -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var settings: MailServerSettings?
    @State private var stage = Stage.account(failure: nil)
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
                TextField(Self.string("Email", "Other account: the address field"), text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                SecureField(Self.string("Password", "Other account: the password field"), text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
            } footer: {
                // Always one Text, so the section keeps its identity between stages and the secure field keeps
                // showing what was typed.
                if case .servers(found: false, _) = stage {
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
            if let settings = Binding($settings), stage != .discovering, !isOnAccount {
                ServerSettingsSections(settings: settings)
                    .allowsHitTesting(!stage.isBusy)
            }
            if let failure {
                Section {
                    Text(failure).foregroundStyle(.red)
                }
            }
        }
        .onSubmit { submit() }
        // SwiftUI owns the work: it starts when the stage turns busy and is cancelled if the form goes away.
        .task(id: stage) {
            switch stage {
            case .discovering: await discoverAndSignIn()
            case .checking: await check()
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
                        if isOnAccount {
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
                }
            }
        }
    }

    private var isOnAccount: Bool {
        if case .account = stage { true } else { false }
    }

    private var failure: String? {
        switch stage {
        case .account(let failure), .servers(_, let failure): failure
        case .discovering, .checking: nil
        }
    }

    private var canSubmit: Bool {
        guard !stage.isBusy, email.contains("@"), !password.isEmpty else { return false }
        guard !isOnAccount, let settings else { return true }
        return !settings.imap.host.isEmpty && !settings.smtp.host.isEmpty && !settings.username.isEmpty
            && settings.imap.port != 0 && settings.smtp.port != 0
    }

    private func submit() {
        guard canSubmit else { return }
        stage = isOnAccount ? .discovering : .checking
    }

    /// Signs in with the servers the lookup found. Without any, or when they don't answer, the servers are asked
    /// for; a refused password is asked for again, since the servers that refused it are most likely right.
    private func discoverAndSignIn() async {
        guard let found = await discover(email) else {
            settings = guess(email)
            stage = .servers(found: false, failure: nil)
            return
        }
        guard !Task.isCancelled else { return }
        settings = found
        await signIn(with: found) { failure in
            if case .refused = failure { return .account(failure: Self.message(for: failure)) }
            return .servers(found: true, failure: Self.message(for: failure))
        }
    }

    private func check() async {
        guard let settings else { return }
        await signIn(with: settings) { .servers(found: true, failure: Self.message(for: $0)) }
    }

    private func signIn(
        with settings: MailServerSettings, onFailure: (OtherAccountSignInFailure) -> Stage
    ) async {
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
            stage = onFailure(failure)
        } catch is CancellationError {
            return
        } catch {
            stage = .servers(found: true, failure: error.localizedDescription)
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
