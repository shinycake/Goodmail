import MailCore
import MailUI
import SwiftUI
import WidgetKit

/// The newest Inbox conversations of every account, each with buttons to open or archive it.
struct InboxWidget: Widget {
    static let kind = "Inbox"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Provider()) { entry in
            InboxWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Inbox")
        .description("Your newest mail.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }

    struct Entry: TimelineEntry {
        let date: Date
        let content: InboxSnapshot
    }

    /// Reads the shared database once per timeline; the app asks for a new one after each sync.
    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now, content: .placeholder) }

        func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> Void) {
            guard !context.isPreview else { return completion(Entry(date: .now, content: .placeholder)) }
            // Unowned on purpose. Safe: WidgetKit owns the request through `completion`, which runs exactly once, and
            // the read can't fail or be cancelled; it reads off the main actor (`InboxSnapshot.load`).
            Task { @concurrent in completion(Entry(date: .now, content: await InboxSnapshot.load())) }
        }

        func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> Void) {
            // Unowned on purpose, as in `getSnapshot`.
            Task { @concurrent in
                completion(Timeline(entries: [Entry(date: .now, content: await InboxSnapshot.load())], policy: .never))
            }
        }
    }
}

struct InboxWidgetView: View {
    let entry: InboxWidget.Entry
    @Environment(\.widgetFamily) private var family

    private var rowCount: Int { family == .systemLarge ? 6 : 2 }

    var body: some View {
        switch entry.content {
        case .noAccounts:
            ContentUnavailableView("No Accounts", systemImage: "envelope")
        case .unavailable:
            ContentUnavailableView("Mail Unavailable", systemImage: "exclamationmark.triangle")
        case .inbox(let rows) where rows.isEmpty:
            ContentUnavailableView("Inbox Zero", systemImage: "tray")
        case .inbox(let rows):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.prefix(rowCount)) { row in
                    InboxWidgetRow(row: row)
                    if row.id != rows.prefix(rowCount).last?.id { Divider() }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct InboxWidgetRow: View {
    let row: InboxSnapshot.Row

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(row.thread.isUnread ? Color(uiColor: row.color.uiColor) : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            ThreadButton(row: row) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.thread.sender.displayName).font(
                            .subheadline.weight(row.thread.isUnread ? .semibold : .regular))
                        Spacer(minLength: 4)
                        Text(row.thread.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(row.thread.subject).font(.subheadline).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            ArchiveButton(row: row)
        }
    }
}
