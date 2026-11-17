import MailCore
import MailWrist
import SwiftUI

/// Below the Inbox, how fresh the mail the watch reads itself is (ADR-023): when it last checked, that it is checking,
/// or why it can't.
struct WristFreshnessFooter: View {
    let freshness: WristFreshness

    var body: some View {
        VStack(spacing: 2) {
            switch freshness {
            case .current(let checkedAt):
                Updated(at: checkedAt)
            case .checking:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(
                        "Checking for Mail…", tableName: "Wrist", bundle: .module,
                        comment: "Below the Inbox while the watch checks for new mail itself")
                }
            case .behind(let reason, let lastChecked):
                Text(
                    "Can’t Check Mail", tableName: "Wrist", bundle: .module,
                    comment: "Below the Inbox when the watch's own checks for mail keep failing"
                )
                .foregroundStyle(.primary)
                reason.text
                if let lastChecked { Updated(at: lastChecked) }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// "Updated 2 min. ago", kept current as time passes.
private struct Updated: View {
    let date: Date

    init(at date: Date) {
        self.date = date
    }

    var body: some View {
        TimelineView(.everyMinute) { _ in
            Text(
                "Updated \(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))",
                tableName: "Wrist", bundle: .module,
                comment: "Below the Inbox: when the watch last checked for mail itself, as in “Updated 2 min. ago”")
        }
    }
}

#Preview("Updated") {
    List {
        Section {
        } footer: {
            WristFreshnessFooter(freshness: .current(checkedAt: .now - 120))
        }
    }
}

#Preview("Checking") {
    List {
        Section {
        } footer: {
            WristFreshnessFooter(freshness: .checking(lastChecked: .now - 600))
        }
    }
}

#Preview("Can’t check") {
    List {
        Section {
        } footer: {
            WristFreshnessFooter(freshness: .behind(.serverUnreachable, lastChecked: .now - 3_600))
        }
    }
}

#Preview("Sign in again") {
    List {
        Section {
        } footer: {
            WristFreshnessFooter(freshness: .behind(.signInFailed, lastChecked: nil))
        }
    }
}
