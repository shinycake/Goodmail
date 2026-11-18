import MailCore
import SwiftUI

/// The Apple Watch section of Settings: one switch, and a note when account sharing is off, since the watch gets its
/// sign-ins through iCloud Keychain.
struct WatchSection: View {
    @Bindable var choices: WatchChoices
    /// Whether this iPhone shares its sign-ins (`AccountSharingMode.shares`).
    let sharesSignIns: Bool

    var body: some View {
        Section {
            Toggle(isOn: $choices.mailWithoutIPhone) {
                Text(
                    "Mail Without iPhone", tableName: "Watch", bundle: .module,
                    comment: "Setting: the watch reads Gmail and Outlook itself")
            }
        } header: {
            Text("Apple Watch", tableName: "Watch", bundle: .module, comment: "Settings section for the watch app")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "Apple Watch checks Gmail and Outlook itself when your iPhone is off or out of reach. Other accounts need your iPhone.",
                    tableName: "Watch", bundle: .module, comment: "Explains the Mail Without iPhone setting")
                if choices.mailWithoutIPhone && !sharesSignIns {
                    Text(
                        "Turn on account sharing so Apple Watch gets your sign-ins.", tableName: "Watch",
                        bundle: .module, comment: "Shown when account sharing is off, which the watch needs")
                }
            }
        }
    }
}

#Preview {
    Form { WatchSection(choices: WatchChoices {}, sharesSignIns: false) }
}
