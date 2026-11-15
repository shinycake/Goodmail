import MailCore
import SwiftUI

/// A password account's sign-in, to correct in Settings: an Other Mail Account's servers and password, or iCloud's
/// app-specific password. Save logs in first and keeps the change only when the servers accept it, so a typo can't
/// leave the account unable to read or send.
struct ServerSettingsView: View {
    @State private var editor: ServerSettingsEditor
    @Environment(\.dismiss) private var dismiss

    /// The editor is made once for this screen; the login it edits doesn't change while it shows.
    init(service: ServerSettingsEditor.Service) {
        _editor = State(initialValue: ServerSettingsEditor(service: service))
    }

    var body: some View {
        content
            .navigationTitle(Self.title(editor.service.kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if editor.isSaving {
                        ProgressView()
                    } else {
                        Button(role: .confirm) {
                            editor.submit()
                        } label: {
                            Text(
                                "Save", tableName: "ServerSettings", bundle: .module,
                                comment: "Checks the edited servers and keeps them")
                        }
                        .disabled(!editor.canSave)
                    }
                }
            }
            .onAppear { editor.load() }
            // SwiftUI owns the check: it starts when Save is tapped and is cancelled if the screen goes away.
            .task(id: editor.state) {
                switch editor.state {
                case .saving: await editor.save()
                case .saved: dismiss()
                case .loading, .loadFailed, .editing: break
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch editor.state {
        case .loading, .saved:
            ProgressView()
        case .loadFailed:
            ContentUnavailableView {
                Label {
                    Text(
                        "No Sign-In on This Device", tableName: "ServerSettings", bundle: .module,
                        comment: "Shown when the account's servers and password can't be read")
                } icon: {
                    Image(systemName: "key.slash")
                }
            } description: {
                Text(
                    "Remove the account and add it again.", tableName: "ServerSettings", bundle: .module,
                    comment: "What to do when the account's sign-in is missing")
            }
        case .editing, .saving:
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                SecureField(
                    OtherAccountSignInView.string("Password", "Other account: the password field"),
                    text: $editor.draft.password
                )
                .textContentType(.password)
                // Passwords are mostly Latin, so a Hebrew or other keyboard isn't the one it opens with.
                .keyboardType(.asciiCapable)
            } footer: {
                switch editor.service.kind {
                case .servers:
                    Text(
                        "Goodmail logs in to both servers before it saves a change.", tableName: "ServerSettings",
                        bundle: .module, comment: "Explains that Save checks the servers first")
                case .appPassword:
                    Text(
                        "Use an app-specific password from your Apple Account. Goodmail checks it with iCloud before it saves it.",
                        tableName: "ServerSettings", bundle: .module,
                        comment: "Explains the iCloud app-specific password and that Save checks it first")
                }
            }
            if let settings = editor.draft.settings {
                ServerSettingsSections(
                    settings: Binding(get: { editor.draft.settings ?? settings }, set: { editor.draft.settings = $0 }))
            }
            if let failure = editor.failure {
                Section {
                    Text(OtherAccountSignInView.message(for: failure)).foregroundStyle(.red)
                }
            }
        }
        // Disabling the fields while checking leaves the secure field blank once it's enabled again, so they only
        // stop taking touches.
        .allowsHitTesting(!editor.isSaving)
        .onSubmit { editor.submit() }
    }

    static func title(_ kind: ServerSettingsEditor.Kind) -> Text {
        switch kind {
        case .servers:
            Text(
                "Server Settings", tableName: "ServerSettings", bundle: .module,
                comment: "Title of an account's IMAP and SMTP server settings")
        case .appPassword:
            Text(
                "App-Specific Password", tableName: "ServerSettings", bundle: .module,
                comment: "Title of the screen that changes an iCloud account's app-specific password")
        }
    }
}
