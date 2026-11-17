import Foundation
import MailCore
import MailWrist
import MailWristUI
import SwiftUI
import WidgetKit

/// The watch face complications and the Smart Stack card (ADR-022): the Inbox at a glance, from the mailbox the watch
/// app stores in the App Group. The app asks for a new timeline after each save.
@main
struct GoodmailWatchWidgets: WidgetBundle {
    var body: some Widget {
        InboxGlanceWidget()
    }
}

struct InboxGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Inbox", provider: InboxGlanceProvider()) { entry in
            WristGlanceView(glance: entry.glance)
                .containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Inbox")
        .description("Unread mail at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct InboxGlanceEntry: TimelineEntry {
    let glance: WristGlance

    var date: Date { glance.date }
    /// Raises the Smart Stack card for a fresh code or new mail.
    var relevance: TimelineEntryRelevance? { TimelineEntryRelevance(score: Float(glance.relevance)) }
}

struct InboxGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> InboxGlanceEntry { Self.sample }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (InboxGlanceEntry) -> Void) {
        guard !context.isPreview else { return completion(Self.sample) }
        // WidgetKit owns the result through `completion`; the task ends when it is called.
        Task { completion(await Self.entries(now: .now)[0]) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<InboxGlanceEntry>) -> Void) {
        // WidgetKit owns the result through `completion`; the task ends when it is called.
        Task { completion(Timeline(entries: await Self.entries(now: .now), policy: .never)) }
    }

    /// The stored mailbox's glance now and the calmer ones it steps down to; never empty.
    private static func entries(now: Date) async -> [InboxGlanceEntry] {
        let shown: WristSnapshot? =
            if let directory = SharedContainer.directoryURL {
                await WristStore(directory: directory).load().shown
            } else {
                nil
            }
        return WristGlance.timeline(for: shown, now: now).map(InboxGlanceEntry.init)
    }

    /// What the gallery and a loading face show.
    private static var sample: InboxGlanceEntry {
        #if DEBUG
            let snapshot: WristSnapshot? = .sample(.english)
        #else
            let snapshot: WristSnapshot? = nil
        #endif
        return InboxGlanceEntry(glance: WristGlance.timeline(for: snapshot, now: .now)[0])
    }
}
