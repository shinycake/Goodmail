import MailCore
import SwiftUI
import UIKit

/// What the account counts toward the app's badge, as a checked list, like Mail's Badge App Icon. When the reader
/// turned badges off in iOS Settings, it says so and links there, since only they can turn them back on.
struct BadgeSection: View {
    let choices: BadgeChoices
    let account: Account
    /// Whether the account's Inbox is sorted into categories, which Primary Only needs.
    let sorted: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if let source = choices.choice(for: account.id) {
                Picker(selection: Binding(get: { source }, set: { choices.set($0, for: account.id) })) {
                    ForEach(BadgeChoices.choices(for: account, sorted: sorted, current: source), id: \.self) {
                        Text(BadgeChoices.title($0)).tag($0)
                    }
                } label: {
                    Text(
                        "Badge App Icon", tableName: "Badge", bundle: .module,
                        comment: "Settings section for what an account counts on the app's icon")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            if choices.isTurnedOffInSettings,
                let settings = URL(string: UIApplication.openNotificationSettingsURLString)
            {
                Button {
                    openURL(settings)
                } label: {
                    Text(
                        "Turn On in Settings", tableName: "Badge", bundle: .module,
                        comment: "Opens iOS Settings to allow the app badge")
                }
            }
        } header: {
            Text(
                "Badge App Icon", tableName: "Badge", bundle: .module,
                comment: "Settings section for what an account counts on the app's icon")
        } footer: {
            // Nothing until iOS has answered, so the footer doesn't change its words under the reader.
            switch choices.status {
            case .loading:
                EmptyView()
            case .loaded(_, turnedOff: true):
                Text(
                    "Badges for Goodmail are turned off in Settings.", tableName: "Badge", bundle: .module,
                    comment: "Explains why the app's icon shows no count")
            case .loaded(_, turnedOff: false):
                Text(
                    "The number on Goodmail's icon counts unread mail from every account.", tableName: "Badge",
                    bundle: .module, comment: "Explains the app badge setting")
            }
        }
        .loads(choices)
    }
}
