import MailCore
import MailWrist
import SwiftUI
import WidgetKit

/// The rectangular complication and the Smart Stack card: the newest unread conversation, or a fresh code big.
/// Sender, subject, preview and code hide while the watch is locked; the count stays.
struct WristGlanceCard: View {
    let content: WristGlance.Content

    var body: some View {
        switch content {
        case .waiting:
            Label {
                Text(verbatim: "–")
            } icon: {
                Image(systemName: "envelope.fill").widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WristGlanceText.waiting)
        case .caughtUp(let since):
            VStack(alignment: .leading) {
                Label {
                    Text(
                        "All Caught Up", tableName: "Wrist", bundle: .module, comment: "Shown when the Inbox is empty")
                } icon: {
                    Image(systemName: "tray").widgetAccentable()
                }
                .font(.headline)
                Text(since, style: .time).font(.caption).foregroundStyle(.secondary)
            }
        case .unread(let count, let newest):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(newest.sender.displayName).font(.headline).lineLimit(1).privacySensitive()
                    Spacer(minLength: 2)
                    Text(count, format: .number).font(.headline).widgetAccentable()
                        .accessibilityLabel(WristGlanceText.unread(count))
                }
                Text(newest.subject).font(.caption).lineLimit(1).privacySensitive()
                Text(newest.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
            }
        case .code(let code, let from, _):
            VStack(alignment: .leading, spacing: 0) {
                Text(from.sender.displayName).font(.caption).lineLimit(1).privacySensitive()
                Text(verbatim: code)
                    // Digit by digit, as it's typed, not as one big number.
                    .speechSpellsOutCharacters()
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                    .privacySensitive()
            }
        }
    }
}
