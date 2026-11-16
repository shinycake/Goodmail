import MailCore
import SwiftUI

/// Accounts, the mail list and sending, as a system form.
struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var removing: Account?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(model.accounts) { account in
                    NavigationLink(value: account.id) {
                        Label {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(account.name ?? account.email)
                                    if account.name != nil {
                                        Text(account.email).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                // The account's color, which tints its mail and mailboxes.
                                Circle().fill(Color(account.color.uiColor)).frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                            }
                        } icon: {
                            ServiceLogo(service: account.service)
                        }
                    }
                    .swipeActions { removeButton(account) }
                    .contextMenu { removeButton(account) }
                }
                NavigationLink {
                    AddAccountView(model: model)
                } label: {
                    Label {
                        Text(
                            "Add Account", tableName: "Settings", bundle: .module, comment: "Adds another mail account")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            } header: {
                Text(
                    "Accounts", tableName: "Settings", bundle: .module, comment: "Settings section listing the accounts"
                )
            }

            Section {
                Picker(selection: $model.rowDisplay.previewLines) {
                    ForEach(RowDisplay.previewLineChoices, id: \.self) { lines in
                        Text(RowDisplay.previewTitle(lines)).tag(lines)
                    }
                } label: {
                    Text(
                        "Preview", tableName: "Settings", bundle: .module,
                        comment: "Setting for how much of each message a mailbox row shows")
                }
                Toggle(isOn: $model.rowDisplay.showsAvatars) {
                    Text(
                        "Avatars", tableName: "Settings", bundle: .module,
                        comment: "Setting for the sender's initials beside each row")
                }
                NavigationLink {
                    SwipeSettingsView(model: model)
                } label: {
                    Text(SwipeSettingsView.title)
                }
            } header: {
                Text(
                    "Mail List", tableName: "Settings", bundle: .module,
                    comment: "Settings section for how mailbox rows look")
            } footer: {
                Text(
                    "Without avatars, a dot beside a row still marks unread mail.", tableName: "Settings",
                    bundle: .module,
                    comment: "Explains turning avatars off")
            }

            let categorised = model.categorisedAccounts
            if !categorised.isEmpty { InboxCategoriesSection(model: model, accounts: categorised) }

            if model.accounts.count > 1 { ThemeSection(model: model) }

            Section {
                Picker(selection: $model.conversationLayout) {
                    ForEach(ConversationLayout.allCases, id: \.self) { layout in
                        Text(layout.title).tag(layout)
                    }
                } label: {
                    Text(
                        "Layout", tableName: "Settings", bundle: .module,
                        comment: "Setting for how a conversation reads")
                }
            } header: {
                Text(
                    "Conversations", tableName: "Settings", bundle: .module,
                    comment: "Settings section for how conversations read")
            } footer: {
                Text(
                    "Chat shows each message's new words as bubbles. Switch one conversation from its toolbar.",
                    tableName: "Settings", bundle: .module, comment: "Explains the conversation layout setting")
            }

            RemoteImagesSection()

            Section {
                Picker(selection: $model.removalAnimation) {
                    ForEach(RemovalAnimation.allCases, id: \.self) { animation in
                        Text(animation.title).tag(animation)
                    }
                } label: {
                    Text(
                        "Delete & Archive", tableName: "Settings", bundle: .module,
                        comment: "Setting for how trashed, archived and deleted threads leave the list")
                }
            } header: {
                Text(
                    "Animations", tableName: "Settings", bundle: .module,
                    comment: "Settings section for the app's animations")
            } footer: {
                Text(
                    "Playful puts mail into the trash can or archive box, and dissolves mail deleted forever. Subtle slides it away.",
                    tableName: "Settings", bundle: .module, comment: "Explains the delete and archive animation setting"
                )
            }

            Section {
                Picker(selection: $model.undoSendSeconds) {
                    ForEach(Preferences.undoSendChoices, id: \.self) { seconds in
                        Text(SettingsViewModel.undoSendTitle(seconds)).tag(seconds)
                    }
                } label: {
                    Text(
                        "Undo Send", tableName: "Settings", bundle: .module,
                        comment: "Setting for how long a sent message can be taken back")
                }
            } footer: {
                Text(
                    "How long a sent message waits, so you can take it back.", tableName: "Settings", bundle: .module,
                    comment: "Explains the Undo Send setting")
            }
        }
        .navigationDestination(for: AccountID.self) { AccountSettingsView(model: model, accountID: $0) }
        .navigationTitle(
            Text("Settings", tableName: "Settings", bundle: .module, comment: "Title of the settings screen")
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { dismiss() }
            }
        }
        .removeAccountConfirmation($removing, model: model)
        .alert(
            Text(
                "Something Went Wrong", tableName: "Settings", bundle: .module,
                comment: "Title of a settings failure alert"),
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
        ) {
        } message: {
            Text(model.error?.localizedDescription ?? "")
        }
    }
}

extension SettingsView {
    private func removeButton(_ account: Account) -> some View {
        Button(role: .destructive) {
            removing = account
        } label: {
            Label {
                Text(
                    "Remove Account", tableName: "Settings", bundle: .module,
                    comment: "Removes an account from the device")
            } icon: {
                Image(systemName: "minus.circle")
            }
        }
    }
}

/// The settings screen, for UIKit to present.
public enum SettingsScreen {
    public static func make(model: SettingsViewModel, at page: SettingsPage = .main) -> UIViewController {
        Controller(model: model, page: page)
    }

    private struct Root: View {
        let model: SettingsViewModel
        /// The pages pushed over the first screen. Seeded once from the page Settings opens at; the reader moves on
        /// from there.
        @State private var path: [SettingsPage]

        init(model: SettingsViewModel, page: SettingsPage) {
            self.model = model
            _path = State(initialValue: page == .main ? [] : [page])
        }

        var body: some View {
            NavigationStack(path: $path) {
                SettingsView(model: model)
                    .navigationDestination(for: SettingsPage.self) { page in
                        switch page {
                        case .main: SettingsView(model: model)
                        case .swipeActions: SwipeSettingsView(model: model)
                        }
                    }
            }
        }
    }

    /// Tells the model the screen closed only when the screen itself is dismissed. The root view also goes off
    /// screen when an account or Add Account is pushed over it, and treating that as closing rebuilt the mail
    /// screens under the open sheet, which took Settings down with them.
    private final class Controller: UIHostingController<Root> {
        private let model: SettingsViewModel

        init(model: SettingsViewModel, page: SettingsPage) {
            self.model = model
            super.init(rootView: Root(model: model, page: page))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed { model.didClose() }
        }
    }
}
