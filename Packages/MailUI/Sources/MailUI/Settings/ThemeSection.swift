import MailCore
import SwiftUI

/// What views that span accounts, such as the unified inbox, wear: a gradient through every account's color, or one
/// color the reader picks. Only shown with more than one account, since a single account's views wear its own color.
struct ThemeSection: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        Section {
            Toggle(isOn: $model.wearsGradient) {
                Label {
                    Text(
                        "Gradient", tableName: "Settings", bundle: .module,
                        comment: "Setting for a gradient of every account's color")
                } icon: {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: model.gradient.colors.map { Color($0.uiColor) }, startPoint: .leading,
                                endPoint: .trailing)
                        )
                        .frame(width: 24, height: 12)
                        .accessibilityHidden(true)
                }
            }
            if case .solid(let color) = model.combinedTheme {
                ColorChoices(selection: color) { model.combinedTheme = .solid($0) }
            }
        } header: {
            Text(
                "Theme", tableName: "Settings", bundle: .module,
                comment: "Settings section for the color of views showing every account")
        } footer: {
            Text(
                "Views that show every account, like the unified inbox, wear a gradient of your account colors. Turn it off to choose one color.",
                tableName: "Settings", bundle: .module, comment: "Explains the Gradient setting")
        }
    }
}
