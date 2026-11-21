import MailCore
import SwiftUI
import UIKit

/// General's rows that only a Mac has. Nothing here syncs, and the footer says so.
struct DesktopSettingsSection: View {
    @Bindable var settings: DesktopSettings

    var body: some View {
        Section {
            Toggle(
                isOn: Binding(get: { settings.openAtLogin.isOn }, set: { settings.setOpensAtLogin($0) })
            ) {
                Text(
                    "Open at Login", tableName: "Desktop", bundle: .module,
                    comment: "Setting for opening the app when the Mac starts")
            }
            .disabled(settings.openAtLogin == .unavailable)
            if settings.openAtLogin == .needsApproval {
                Button {
                    settings.openLoginItemsSettings()
                } label: {
                    Text(
                        "Needs approval in System Settings", tableName: "Desktop", bundle: .module,
                        comment: "Opens System Settings at Login Items so the reader can allow the app")
                }
            }
            if case .failed(let message) = settings.openAtLogin {
                Text(message).foregroundStyle(.secondary)
            }
            Toggle(isOn: $settings.doubleClickOpensWindow) {
                Text(
                    "Double-Click Opens a Window", tableName: "Desktop", bundle: .module,
                    comment: "Setting for opening a conversation in its own window with a double-click")
            }
            Picker(selection: $settings.deleteKey) {
                ForEach(DeleteKeyAction.allCases, id: \.self) { choice in
                    Text(Self.title(choice)).tag(choice)
                }
            } label: {
                Text(
                    "Delete Key", tableName: "Desktop", bundle: .module,
                    comment: "Setting for what the Delete key does to the picked conversations")
            }
        } header: {
            Text("This Mac", tableName: "Desktop", bundle: .module, comment: "Settings section for choices of this Mac")
        } footer: {
            Text(
                "These stay on this Mac. In Trash, Delete removes mail for good.", tableName: "Desktop",
                bundle: .module, comment: "Explains that the Mac's settings don't sync, and what Delete does in Trash")
        }
        // The reader may have approved or removed the login item in System Settings while the window was behind.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            settings.refresh()
        }
    }

    static func title(_ choice: DeleteKeyAction) -> String {
        switch choice {
        case .trash:
            String(localized: "Move to Trash", table: "Desktop", bundle: .module, comment: "What Delete does: trash")
        case .archive:
            String(localized: "Archive", table: "Desktop", bundle: .module, comment: "What Delete does: archive")
        }
    }
}
