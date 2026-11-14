import MailCore
import SwiftUI

/// The Signature row of an account's settings: what new mail from the account ends with, its first line shown.
struct SignatureRow: View {
    let signatures: Signatures
    let account: Account

    var body: some View {
        NavigationLink {
            SignatureEditor(signatures: signatures, account: account)
        } label: {
            LabeledContent {
                Text(preview).lineLimit(1)
            } label: {
                Text(
                    "Signature", tableName: "Signatures", bundle: .module,
                    comment: "An account's signature: its settings row and its editor's title")
            }
        }
        .task { await signatures.load(account.id) }
    }

    private var preview: String {
        let text = signatures.entries[account.id]?.text ?? ""
        guard let first = text.split(separator: "\n").first else {
            return String(
                localized: "None", table: "Signatures", bundle: .module,
                comment: "Shown on the Signature row when the account has no signature")
        }
        return String(first)
    }
}

/// Edits one account's signature, saved as the editor closes, as Mail's own signature setting does.
private struct SignatureEditor: View {
    let signatures: Signatures
    let account: Account

    var body: some View {
        Form {
            Section {
                if let entry = signatures.entries[account.id] {
                    SignatureText(initial: entry.text) { signatures.save($0, for: account.id) }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } footer: {
                footer
            }
        }
        .navigationTitle(
            Text(
                "Signature", tableName: "Signatures", bundle: .module,
                comment: "An account's signature: its settings row and its editor's title")
        )
        .navigationBarTitleDisplayMode(.inline)
        .task { await signatures.load(account.id) }
    }

    @ViewBuilder private var footer: some View {
        if account.service.syncsSignature {
            Text(
                "Syncs with Gmail. A signature changed here replaces Gmail's formatting with plain text.",
                tableName: "Signatures", bundle: .module,
                comment: "Explains that a Gmail signature is shared with Gmail")
        } else {
            Text(
                "Kept on this device. Outlook and iCloud don't share their signatures with other apps.",
                tableName: "Signatures", bundle: .module,
                comment: "Explains that an Outlook or iCloud signature stays in this app")
        }
    }
}

/// The signature's text, starting from what is stored; `save` takes the text when the editor goes away.
private struct SignatureText: View {
    /// Seeds the text once; later changes to the stored signature don't overwrite what's being typed.
    let initial: String
    let save: (String) -> Void
    @State private var text: String

    init(initial: String, save: @escaping (String) -> Void) {
        self.initial = initial
        self.save = save
        _text = State(initialValue: initial)
    }

    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: 160)
            .accessibilityLabel(
                Text(
                    "Signature", tableName: "Signatures", bundle: .module,
                    comment: "An account's signature: its settings row and its editor's title")
            )
            .onDisappear { save(text) }
    }
}
