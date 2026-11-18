import SwiftUI

/// Turns the faint doodles in Settings and Mailboxes on or off. The welcome screen and Inbox Zero keep theirs, since
/// there they are the picture rather than decoration. The choice follows the reader to their other devices.
struct DoodlesSection: View {
    @AppStorage(Preferences.showsDoodlesKey) private var showsDoodles = true

    var body: some View {
        Section {
            Toggle(isOn: $showsDoodles) {
                Text(
                    "Doodles", tableName: "Settings", bundle: .module,
                    comment: "Setting for the faint decorative doodles")
            }
        } footer: {
            Text(
                "Faint sketches in the corners of Settings and Mailboxes. Welcome and Inbox Zero always keep theirs.",
                tableName: "Settings", bundle: .module, comment: "Explains the Doodles setting")
        }
    }
}
