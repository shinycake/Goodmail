import MailCore
import SwiftUI

/// An account's automatic reply: on or off, between which dates, what it says, and to whom. Saved to the service
/// with Save, since the service is what sends it.
struct AutoReplyView: View {
    @State private var editor: AutoReplyEditor
    /// Each Try Again counts up, and the load runs again in a task the screen owns.
    @State private var loadAttempt = 0

    /// The editor is made once for this screen; the service it talks to doesn't change while it shows.
    init(service: AutoReplyEditor.Service) {
        _editor = State(initialValue: AutoReplyEditor(service: service))
    }

    var body: some View {
        content
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if editor.isSaving {
                        ProgressView()
                    } else {
                        Button(role: .confirm) {
                            editor.save()
                        } label: {
                            Text("Save", tableName: "AutoReply", bundle: .module, comment: "Saves the automatic reply")
                        }
                        .disabled(!editor.hasChanges)
                    }
                }
            }
            .alert(
                Text(
                    "Couldn’t Save Automatic Reply", tableName: "AutoReply", bundle: .module,
                    comment: "Alert title when the service refuses the automatic reply"),
                isPresented: Binding(
                    get: { editor.saveFailure != nil }, set: { if !$0 { editor.dismissSaveFailure() } })
            ) {
                Button(role: .cancel) {
                } label: {
                    Text("OK", tableName: "AutoReply", bundle: .module, comment: "Dismiss")
                }
            } message: {
                Text(editor.saveFailure ?? "")
            }
            .task(id: loadAttempt) { await editor.load() }
    }

    @ViewBuilder private var content: some View {
        switch editor.state {
        case .loading:
            ProgressView()
        case .loadFailed:
            ContentUnavailableView {
                Label {
                    Text(
                        "Couldn’t Load Automatic Reply", tableName: "AutoReply", bundle: .module,
                        comment: "Shown when the automatic reply can't be read")
                } icon: {
                    Image(systemName: "exclamationmark.bubble")
                }
            } description: {
                Text(
                    "Check your connection and try again.", tableName: "AutoReply", bundle: .module,
                    comment: "Explains a failed load of the automatic reply")
            } actions: {
                Button {
                    loadAttempt += 1
                } label: {
                    Text("Try Again", tableName: "AutoReply", bundle: .module, comment: "Loads the reply again")
                }
            }
        case .editing, .saving:
            AutoReplyForm(editor: editor)
        }
    }

    static var title: Text {
        Text(
            "Automatic Reply", tableName: "AutoReply", bundle: .module,
            comment: "Title of an account's away-message setting")
    }
}

/// The fields, shown once the service's reply is in.
private struct AutoReplyForm: View {
    @Bindable var editor: AutoReplyEditor

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $editor.isOn) { AutoReplyView.title }
            } footer: {
                Text(
                    "Replies to new mail for you, from the mail service, even while this iPhone is off.",
                    tableName: "AutoReply", bundle: .module, comment: "Explains the automatic reply")
            }
            if editor.isOn {
                Section {
                    Toggle(isOn: $editor.isScheduled) {
                        Text(
                            "Only During These Dates", tableName: "AutoReply", bundle: .module,
                            comment: "Limits the automatic reply to a date range")
                    }
                    if editor.isScheduled {
                        DatePicker(selection: $editor.start) {
                            Text("Starts", tableName: "AutoReply", bundle: .module, comment: "Reply start date")
                        }
                        DatePicker(selection: $editor.end, in: editor.start...) {
                            Text("Ends", tableName: "AutoReply", bundle: .module, comment: "Reply end date")
                        }
                    }
                }
            }
            Section {
                if editor.service.hasSubject {
                    TextField(
                        text: $editor.draft.subject,
                        prompt: Text(
                            "Subject", tableName: "AutoReply", bundle: .module,
                            comment: "Placeholder for the automatic reply's subject")
                    ) {
                        Text(
                            "Subject", tableName: "AutoReply", bundle: .module,
                            comment: "Placeholder for the automatic reply's subject")
                    }
                }
                TextField(
                    text: $editor.draft.message,
                    prompt: Text(
                        "I’m away and will reply when I’m back.", tableName: "AutoReply", bundle: .module,
                        comment: "Placeholder for the automatic reply's message"),
                    axis: .vertical
                ) {
                    Text("Message", tableName: "AutoReply", bundle: .module, comment: "The automatic reply's text")
                }
                .lineLimit(4...)
            } header: {
                Text("Message", tableName: "AutoReply", bundle: .module, comment: "The automatic reply's text")
            }
            Section {
                Toggle(isOn: $editor.draft.contactsOnly) {
                    Text(
                        "Only Reply to My Contacts", tableName: "AutoReply", bundle: .module,
                        comment: "Sends the automatic reply only to the reader's contacts")
                }
            }
        }
        .disabled(editor.isSaving)
    }
}
