import MailCore
import MailWrist
import SwiftUI

/// What else can be done to a conversation from the wrist: pin or unpin it, or snooze it until a time that suits.
/// A snooze takes it out of the Inbox, so the conversation closes after one.
struct WristMoreSheet: View {
    let row: WristRow
    let inbox: WristInboxModel
    /// Called on a snooze instead of closing the sheet: the conversation closes it, then itself, since the snooze
    /// took it away.
    let snoozed: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Button {
                inbox.perform(.pin(!row.isPinned), on: [row])
                dismiss()
            } label: {
                if row.isPinned {
                    Label {
                        Text("Unpin", tableName: "Wrist", bundle: .module, comment: "Unpins a conversation")
                    } icon: {
                        Image(systemName: "pin.slash")
                    }
                } else {
                    Label {
                        Text("Pin", tableName: "Wrist", bundle: .module, comment: "Pins a conversation to the top")
                    } icon: {
                        Image(systemName: "pin")
                    }
                }
            }
            .tint(.orange)
            Section {
                ForEach(LaterTime.snoozeChoices(at: .now), id: \.date) { choice in
                    Button {
                        inbox.perform(.snooze(until: choice.date), on: [row])
                        snoozed()
                    } label: {
                        WristLaterLabel(choice: choice)
                    }
                }
            } header: {
                Text("Snooze Until", tableName: "Wrist", bundle: .module, comment: "Above the snooze times")
            }
        }
    }
}

/// A snooze time: what it's called, and when it is.
private struct WristLaterLabel: View {
    let choice: LaterTime

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                name
                Text(choice.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }

    private var name: Text {
        switch choice {
        case .thisEvening:
            Text("This Evening", tableName: "Wrist", bundle: .module, comment: "Snooze time: 6 PM today")
        case .tonight:
            Text("Tonight", tableName: "Wrist", bundle: .module, comment: "Snooze time: 9 PM today")
        case .tomorrowMorning:
            Text("Tomorrow", tableName: "Wrist", bundle: .module, comment: "Snooze time: 8 AM tomorrow")
        case .thisWeekend:
            Text(
                "This Weekend", tableName: "Wrist", bundle: .module, comment: "Snooze time: the weekend's first morning"
            )
        case .nextWeek:
            Text("Next Week", tableName: "Wrist", bundle: .module, comment: "Snooze time: the morning the week resumes")
        }
    }

    private var symbol: String {
        switch choice {
        case .thisEvening, .tonight: "moon"
        case .tomorrowMorning: "sunrise"
        case .thisWeekend: "sofa"
        case .nextWeek: "briefcase"
        }
    }
}
