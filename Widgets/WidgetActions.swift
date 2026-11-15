import MailCore
import SwiftUI

// The buttons run MailIntents' intents, which the Linux cloud build can't build (docs/setup/cloud-builds.md). There
// the rows type-check with buttons that do nothing; the Mac builds the real ones.
#if canImport(MailIntents)
    import AppIntents
    import MailIntents

    /// Opens the conversation in the app.
    struct ThreadButton<Label: View>: View {
        let row: InboxSnapshot.Row
        @ViewBuilder let label: () -> Label

        var body: some View {
            Button(intent: OpenThreadIntent(target: ThreadEntity(row.thread)), label: label)
        }
    }

    /// Archives the conversation, which leaves the widget at its next timeline.
    struct ArchiveButton: View {
        let row: InboxSnapshot.Row

        var body: some View {
            Button(intent: ArchiveThreadsIntent(threads: [ThreadEntity(row.thread)])) {
                Image(systemName: "archivebox").font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Archive"))
        }
    }
#else
    struct ThreadButton<Label: View>: View {
        let row: InboxSnapshot.Row
        @ViewBuilder let label: () -> Label

        var body: some View { label() }
    }

    struct ArchiveButton: View {
        let row: InboxSnapshot.Row

        var body: some View { EmptyView() }
    }
#endif
