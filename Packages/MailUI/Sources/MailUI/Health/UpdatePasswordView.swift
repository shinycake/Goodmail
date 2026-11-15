import MailCore
import SwiftUI

/// Why a new password didn't work, as the form explains it.
public enum UpdatePasswordFailure: Error {
    /// The server refused the password.
    case wrongPassword
}

/// A new password for an account on an IMAP server that stopped accepting the stored one. Its servers stay as they
/// were set up.
struct UpdatePasswordView: View {
    /// Where the form stands. Only `editing` takes input; a failure stays shown until the next try.
    enum Stage: Equatable {
        case editing(failure: String?)
        case checking
    }

    let email: String
    let update: (_ password: String) async throws -> Void
    let finished: (_ updated: Bool) -> Void

    @State private var password = ""
    @State private var stage = Stage.editing(failure: nil)
    @FocusState private var passwordFocused: Bool

    var body: some View {
        Form {
            Section {
                SecureField(
                    String(
                        localized: "Password", table: "Health", bundle: .module,
                        comment: "Update password: the password field"),
                    text: $password
                )
                .textContentType(.password)
                .focused($passwordFocused)
            } header: {
                Text(verbatim: email)
            } footer: {
                Text(
                    "The mail server no longer accepts the saved password. Enter the account’s current password.",
                    tableName: "Health", bundle: .module, comment: "Update password: why it's asked for")
            }
            // Disabling the field while checking leaves it blank once it's enabled again, so it only stops taking
            // touches.
            .allowsHitTesting(stage != .checking)
            if case .editing(let failure?) = stage {
                Section {
                    Text(failure).foregroundStyle(.red)
                }
            }
        }
        .onAppear { passwordFocused = true }
        .onSubmit { if canSubmit { stage = .checking } }
        // SwiftUI owns the check: it starts when the stage turns to checking and is cancelled if the form goes away.
        .task(id: stage) { if stage == .checking { await check() } }
        .navigationTitle(
            Text("Update Password", tableName: "Health", bundle: .module, comment: "Update password: the title")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    finished(false)
                } label: {
                    Text(
                        "Cancel", tableName: "Health", bundle: .module,
                        comment: "Closes the password update without changing it")
                }
                .disabled(stage == .checking)
            }
            ToolbarItem(placement: .confirmationAction) {
                if stage == .checking {
                    ProgressView()
                } else {
                    Button {
                        stage = .checking
                    } label: {
                        Text(
                            "Sign In", tableName: "Health", bundle: .module,
                            comment: "Update password: checks the new password with the server")
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private var canSubmit: Bool {
        stage != .checking && !password.isEmpty
    }

    private func check() async {
        do {
            try await update(password)
            finished(true)
        } catch UpdatePasswordFailure.wrongPassword {
            password = ""
            passwordFocused = true
            stage = .editing(
                failure: String(
                    localized: "The server didn’t accept this password.", table: "Health", bundle: .module,
                    comment: "Update password: the server refused it"))
        } catch {
            stage = .editing(failure: FailureReason.message(for: error))
        }
    }
}

/// The password update, for UIKit to present.
public enum UpdatePasswordScreen {
    /// `update` checks the password with the account's servers and keeps it, throwing
    /// `UpdatePasswordFailure.wrongPassword` when they refuse it. `finished` is called once, with whether it was kept.
    public static func make(
        email: String, update: @escaping (_ password: String) async throws -> Void,
        finished: @escaping (_ updated: Bool) -> Void
    ) -> UIViewController {
        let screen = UIHostingController(
            rootView: NavigationStack { UpdatePasswordView(email: email, update: update, finished: finished) })
        screen.isModalInPresentation = true
        return screen
    }
}
