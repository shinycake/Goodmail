public import MailCore
public import SwiftUI

/// Accounts, the mail list and sending, as a system form.
struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var removing: Account?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsPlacement) private var placement

    var body: some View {
        Form {
            Section {
                ForEach(model.accounts) { account in
                    NavigationLink(value: account.id) {
                        Label {
                            HStack {
                                AccountNames(account: account)
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
                    .accessibilityActions { moveActions(account) }
                }
                // Edit shows each row's handle to drag it by: the long press is the row's context menu. Mailboxes, the
                // unified Inbox and every account picker follow the order.
                .onMove { model.moveAccounts(from: $0, to: $1) }
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
                if let sharing = model.sharing { OtherDevicesRow(model: model, sharing: sharing) }
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
                    comment: "Settings section for how mailbox rows look"
                )
                .headerDoodle(.star, size: 12, angle: -12, tint: 1)
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
                Picker(selection: $model.afterRemoval) {
                    ForEach(AfterRemoval.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                } label: {
                    Text(
                        "After Archive or Delete", tableName: "Settings", bundle: .module,
                        comment: "Setting for what opens after the conversation being read is archived or deleted")
                }
            } header: {
                Text(
                    "Conversations", tableName: "Settings", bundle: .module,
                    comment: "Settings section for how conversations read"
                )
                .headerDoodle(.plane, size: 20, tint: 2)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Chat shows each message's new words as bubbles. Switch one conversation from its toolbar.",
                        tableName: "Settings", bundle: .module, comment: "Explains the conversation layout setting")
                    Text(
                        "What opens after you archive, delete, move, snooze or mute the conversation you're reading. Next is the one below it in the list.",
                        tableName: "Settings", bundle: .module, comment: "Explains the After Archive or Delete setting")
                }
            }

            RemoteImagesSection()

            if let rules = model.rules { RulesSection(service: rules) }

            if let storage = model.storage { StorageSection(model: storage) }
            if let watch = model.watch {
                WatchSection(choices: watch, sharesSignIns: model.sharing?.mode.shares ?? false)
            }

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
                    comment: "Settings section for the app's animations"
                )
                .headerDoodle(.sparkle, size: 12, tint: 0)
            } footer: {
                Text(
                    "Playful puts mail into the trash can or archive box, and dissolves mail deleted forever. Subtle slides it away.",
                    tableName: "Settings", bundle: .module, comment: "Explains the delete and archive animation setting"
                )
            }

            DoodlesSection()

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

            if let desktop = model.desktop { DesktopSettingsSection(settings: desktop) }
        }
        .settingsDoodles()
        .navigationDestination(for: AccountID.self) { AccountSettingsView(model: model, accountID: $0) }
        .navigationTitle(
            Text("Settings", tableName: "Settings", bundle: .module, comment: "Title of the settings screen")
        )
        .toolbar {
            if model.accounts.count > 1 {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            // A window of its own closes from its title bar.
            if placement == .cover {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
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
    /// VoiceOver's way to reorder the accounts, one place at a time. Only the moves the account can make are offered.
    @ViewBuilder private func moveActions(_ account: Account) -> some View {
        if account.id != model.accounts.first?.id {
            Button {
                model.moveAccount(account.id, by: -1)
            } label: {
                Text(
                    "Move Up", tableName: "Settings", bundle: .module, comment: "Moves an account one place up the list"
                )
            }
        }
        if account.id != model.accounts.last?.id {
            Button {
                model.moveAccount(account.id, by: 1)
            } label: {
                Text(
                    "Move Down", tableName: "Settings", bundle: .module,
                    comment: "Moves an account one place down the list")
            }
        }
    }

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
    /// Settings, open at `page`, as a cover over the mail screens. It tells `model` it closed once it is dismissed.
    public static func make(model: SettingsViewModel, at page: SettingsPage = .main) -> UIViewController {
        Controller(model: model, page: page)
    }

    /// Settings filling the Settings window, showing the pages `pages` holds, which a request for a page while the
    /// window is open adds to. The window tells `model` it closed as the window closes.
    public static func window(model: SettingsViewModel, pages: SettingsPages) -> UIViewController {
        UIHostingController(rootView: Root(model: model, pages: pages, placement: .ownWindow))
    }

    /// What the system calls the Settings window.
    public static var title: String {
        String(localized: "Settings", table: "Settings", bundle: .module, comment: "Title of the settings screen")
    }

    private struct Root: View {
        let model: SettingsViewModel
        @Bindable var pages: SettingsPages
        let placement: SettingsPlacement

        var body: some View {
            NavigationStack(path: $pages.path) {
                SettingsView(model: model)
                    .navigationDestination(for: SettingsPage.self) { page in
                        switch page {
                        case .main: SettingsView(model: model)
                        case .swipeActions: SwipeSettingsView(model: model)
                        }
                    }
            }
            .environment(\.settingsPlacement, placement)
        }
    }

    /// Tells the model the screen closed only when the screen itself is dismissed. The root view also goes off
    /// screen when an account or Add Account is pushed over it, and treating that as closing rebuilt the mail
    /// screens under the open sheet, which took Settings down with them.
    private final class Controller: UIHostingController<Root> {
        private let model: SettingsViewModel

        init(model: SettingsViewModel, page: SettingsPage) {
            self.model = model
            super.init(rootView: Root(model: model, pages: SettingsPages(at: page), placement: .cover))
            // A page sheet, so Settings gets most of a large iPad's height rather than a small form in the middle.
            modalPresentationStyle = .pageSheet
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed { model.didClose() }
        }
    }
}

extension EnvironmentValues {
    /// Where Settings shows, which decides whether its first screen has a Close button.
    @Entry var settingsPlacement = SettingsPlacement.cover
}
