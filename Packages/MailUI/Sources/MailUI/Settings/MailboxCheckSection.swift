import SwiftUI

/// The switch for the push server's look at a Gmail account's history, with what it can and can't see.
struct MailboxCheckSection: View {
    @State private var check: MailboxCheck

    init(service: MailboxCheck.Service) {
        _check = State(initialValue: MailboxCheck(service: service))
    }

    var body: some View {
        Section {
            switch check.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .unknown:
                Text(
                    "Couldn't reach Goodmail's push server.", tableName: "MailboxCheck", bundle: .module,
                    comment: "Shown when the alert filter's status can't be read"
                )
                .foregroundStyle(.secondary)
            case .off, .on, .changing:
                Toggle(isOn: Binding(get: { isOn }, set: { new in Task { await check.set(new) } })) {
                    Text(
                        "Alert Only for New Mail", tableName: "MailboxCheck", bundle: .module,
                        comment: "Switch that lets the push server skip alerts for reads, archives and deletes")
                }
                .disabled(isChanging)
            }
        } footer: {
            Text(
                "Lets Goodmail's push server read this account's labels and message headers, never message bodies, so reading, archiving or deleting mail doesn't show a “New mail” alert. Google may ask you to turn this on again after a week.",
                tableName: "MailboxCheck", bundle: .module, comment: "Explains the alert filter switch")
        }
        .task { await check.load() }
    }

    private var isOn: Bool {
        switch check.state {
        case .on: true
        case .changing(let to): to
        case .loading, .unknown, .off: false
        }
    }

    private var isChanging: Bool {
        if case .changing = check.state { true } else { false }
    }
}
