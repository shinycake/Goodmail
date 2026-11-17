import MailCore
import SwiftUI

/// The words under the envelopes: "All Caught Up" and a greeting, or, while another category has unread mail, a
/// note of it and a link there. VoiceOver reads the title and line as one heading.
struct InboxZeroCopy: View {
    let pointing: InboxZeroPointer?
    let greeting: InboxZeroGreeting
    /// How far the title and the line have come in: 0 hidden and a little low, 1 in place.
    let title: Double
    let line: Double
    let go: (InboxCategory) -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(heading)
                    .font(.title2.bold())
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .opacity(title)
                    .offset(y: 10 * (1 - title))
                Text(subheading)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .opacity(line)
                    .offset(y: 10 * (1 - line))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("inboxZero.title")
            if let pointing {
                Button {
                    go(pointing.category)
                } label: {
                    Text(
                        "Go to \(pointing.category.title)", tableName: "Mailbox", bundle: .module,
                        comment: "Link from an empty Inbox category to another with unread mail")
                }
                .buttonStyle(.borderless)
                .opacity(line)
            }
        }
        .padding(.horizontal, 24)
    }

    private var heading: String {
        guard pointing != nil else {
            return String(
                localized: "All Caught Up", table: "InboxZero", bundle: .module,
                comment: "Title of the empty Inbox, once every thread has been dealt with")
        }
        return String(
            localized: "Primary Is Clear", table: "InboxZero", bundle: .module,
            comment: "Title of an empty Primary Inbox category while another category has unread mail")
    }

    /// "3 unread in Updates": how much unread mail the other category has. `bundle` is the module's, or in a test one
    /// language's.
    static func unread(in pointing: InboxZeroPointer, bundle: Bundle = .module) -> String {
        String(
            localized: "\(pointing.unread) unread in \(pointing.category.title)", table: "InboxZero", bundle: bundle,
            comment: "Under the title of an empty Primary: how many unread threads another category has, and which")
    }

    private var subheading: String {
        if let pointing { return Self.unread(in: pointing) }
        return switch greeting {
        case .morning:
            String(
                localized: "Enjoy your morning.", table: "InboxZero", bundle: .module,
                comment: "Under All Caught Up, from 5 AM to noon")
        case .afternoon:
            String(
                localized: "Enjoy your afternoon.", table: "InboxZero", bundle: .module,
                comment: "Under All Caught Up, from noon to 5 PM")
        case .evening:
            String(
                localized: "Enjoy your evening.", table: "InboxZero", bundle: .module,
                comment: "Under All Caught Up, from 5 PM to 10 PM")
        case .night:
            String(
                localized: "Good night.", table: "InboxZero", bundle: .module,
                comment: "Under All Caught Up, from 10 PM to 5 AM")
        }
    }
}
