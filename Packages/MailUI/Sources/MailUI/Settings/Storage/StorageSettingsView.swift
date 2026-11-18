import MailCore
import SwiftUI

/// The Settings row that opens Storage.
struct StorageSection: View {
    let model: StorageSettings

    var body: some View {
        Section {
            NavigationLink {
                StorageSettingsView(model: model)
            } label: {
                Text(StorageSettingsView.title)
            }
        }
    }
}

/// How much mail downloads before it's opened, how much the device keeps, and a way to remove it.
struct StorageSettingsView: View {
    @Bindable var model: StorageSettings
    @State private var confirmingClear = false

    static var title: String {
        String(localized: "Storage", table: "Storage", bundle: .module, comment: "Title of the storage settings page")
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: $model.scope) {
                    ForEach(PrefetchScope.allCases, id: \.self) { scope in
                        Text(Self.title(of: scope)).tag(scope)
                    }
                } label: {
                    Text(
                        "Download Ahead", tableName: "Storage", bundle: .module,
                        comment: "Setting for when messages download before they're opened")
                }
            } footer: {
                Text(
                    "Goodmail downloads your newest conversations so they open at once, even offline: up to 500 on Wi-Fi and 50 on cellular. Nothing downloads ahead in Low Data Mode.",
                    tableName: "Storage", bundle: .module, comment: "Explains the Download Ahead setting")
            }

            Section {
                usageRows
                Picker(selection: $model.limit) {
                    ForEach(Preferences.cacheLimitChoices, id: \.self) { bytes in
                        Text(Self.size(bytes)).tag(bytes)
                    }
                } label: {
                    Text(
                        "Keep Up To", tableName: "Storage", bundle: .module,
                        comment: "Setting for the most space downloaded mail may take")
                }
            } header: {
                Text(
                    "Downloaded Mail", tableName: "Storage", bundle: .module,
                    comment: "Section for the space downloaded mail takes")
            } footer: {
                Text(
                    "When it's full, the mail you read longest ago goes first. Mail lists and search keep working, and a message downloads again when you open it.",
                    tableName: "Storage", bundle: .module, comment: "Explains the storage limit")
            }

            Section {
                Button(role: .destructive) {
                    confirmingClear = true
                } label: {
                    Text(
                        "Remove Downloaded Mail", tableName: "Storage", bundle: .module,
                        comment: "Removes the downloaded messages and attachments from the device")
                }
                .disabled(model.phase == .clearing)
            } footer: {
                Text(
                    "Drafts and messages waiting to send stay.", tableName: "Storage", bundle: .module,
                    comment: "Explains what removing downloaded mail keeps")
            }
        }
        .navigationTitle(Self.title)
        .task(id: model.limit) { await model.apply() }
        .confirmationDialog(
            Text(
                "Remove Downloaded Mail?", tableName: "Storage", bundle: .module,
                comment: "Title asking to confirm removing downloaded mail"),
            isPresented: $confirmingClear, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await model.clear() }
            } label: {
                Text(
                    "Remove", tableName: "Storage", bundle: .module, comment: "Confirms removing downloaded mail")
            }
        } message: {
            Text(
                "Messages download again when you open them.", tableName: "Storage", bundle: .module,
                comment: "Says what happens after removing downloaded mail")
        }
    }

    @ViewBuilder private var usageRows: some View {
        let messages = Text(
            "Messages", tableName: "Storage", bundle: .module, comment: "Row: the space downloaded messages take")
        let attachments = Text(
            "Attachments", tableName: "Storage", bundle: .module,
            comment: "Row: the space downloaded attachments and images take")
        switch model.phase {
        case .measured(let usage):
            LabeledContent {
                Text(Self.size(usage.messages))
            } label: {
                messages
            }
            LabeledContent {
                Text(Self.size(usage.attachments))
            } label: {
                attachments
            }
        case .measuring, .clearing:
            LabeledContent {
                ProgressView()
            } label: {
                messages
            }
            LabeledContent {
                ProgressView()
            } label: {
                attachments
            }
        case .failed(.measuring):
            Text(
                "Couldn't measure the downloaded mail.", tableName: "Storage", bundle: .module,
                comment: "Shown when the space downloaded mail takes can't be read"
            )
            .foregroundStyle(.secondary)
        case .failed(.removing):
            Text(
                "Couldn't remove the downloaded mail.", tableName: "Storage", bundle: .module,
                comment: "Shown when downloaded mail couldn't be removed to fit the size chosen, or at all"
            )
            .foregroundStyle(.secondary)
        }
    }

    /// In decimal units, as the system's storage screens count, and "0" rather than "Zero" for nothing. Isolated left
    /// to right, so a right-to-left label keeps the number before its unit: "1 GB", not "GB1".
    static func size(_ bytes: Int) -> String {
        "\u{2066}" + Int64(bytes).formatted(.byteCount(style: .file, spellsOutZero: false)) + "\u{2069}"
    }

    static func title(of scope: PrefetchScope) -> String {
        switch scope {
        case .wifiAndCellular:
            String(
                localized: "Wi-Fi and Cellular", table: "Storage", bundle: .module,
                comment: "Download Ahead choice: on any connection but Low Data Mode")
        case .wifiOnly:
            String(localized: "Wi-Fi Only", table: "Storage", bundle: .module, comment: "Download Ahead choice")
        case .never:
            String(
                localized: "Never", table: "Storage", bundle: .module,
                comment: "Download Ahead choice: messages download only when opened")
        }
    }
}
