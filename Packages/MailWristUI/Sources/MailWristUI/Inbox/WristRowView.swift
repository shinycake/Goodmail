import Foundation
import MailCore
import MailWrist
import SwiftUI

/// A conversation in the watch's Inbox: who, what about, and a line or two of it, marked in its account's color
/// while unread.
struct WristRowView: View {
    let row: WristRow
    let color: Color

    @ScaledMetric(relativeTo: .headline) private var dot = 8.0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if row.isUnread {
                    Circle().fill(color).frame(width: dot, height: dot)
                        .accessibilityLabel(
                            Text("Unread", tableName: "Wrist", bundle: .module, comment: "VoiceOver: an unread row"))
                }
                if row.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                        .accessibilityLabel(
                            Text("Pinned", tableName: "Wrist", bundle: .module, comment: "VoiceOver: a pinned row"))
                }
                Text(row.sender.displayName).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                Text(row.date, format: Self.dateStyle(row.date)).font(.footnote).foregroundStyle(.secondary)
            }
            if !row.subject.isEmpty {
                Text(row.subject).font(.subheadline.weight(row.isUnread ? .semibold : .regular)).lineLimit(1)
            }
            if !row.snippet.isEmpty {
                Text(row.snippet).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The time for today's mail, otherwise the day.
    private static func dateStyle(_ date: Date) -> Date.FormatStyle {
        Calendar.current.isDateInToday(date) ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day()
    }
}
