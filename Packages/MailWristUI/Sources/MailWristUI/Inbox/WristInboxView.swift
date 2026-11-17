import MailCore
public import MailWrist
public import SwiftUI

/// The watch app's first screen: the unified Inbox the iPhone last sent, or why there is none.
public struct WristInboxView: View {
    let model: WristInboxModel
    let threads: WristThreads
    @Bindable var route: WristRoute

    public init(model: WristInboxModel, threads: WristThreads, route: WristRoute) {
        self.model = model
        self.threads = threads
        self.route = route
    }

    public var body: some View {
        NavigationStack(path: $route.path) {
            content
                .navigationTitle(
                    Text("Inbox", tableName: "Wrist", bundle: .module, comment: "The Inbox screen's title")
                )
                .wristUndeliveredAlert(model)
                .navigationDestination(for: ThreadSummary.ID.self) { id in
                    WristThreadView(id: id, threads: threads, inbox: model)
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .waitingForPhone:
            Unavailable(
                title: Text(
                    "Open Goodmail on iPhone", tableName: "Wrist", bundle: .module,
                    comment: "Shown before the iPhone has sent any mail"),
                symbol: "iphone",
                description: Text(
                    "Your mail shows here once the iPhone app has synced.", tableName: "Wrist", bundle: .module,
                    comment: "Shown before the iPhone has sent any mail"))
        case .updateNeeded:
            Unavailable(
                title: Text(
                    "Update Goodmail", tableName: "Wrist", bundle: .module,
                    comment: "Shown when the iPhone app is newer than the watch app"),
                symbol: "arrow.down.circle",
                description: Text(
                    "Your iPhone has a newer Goodmail. Update this app to see your mail.", tableName: "Wrist",
                    bundle: .module, comment: "Shown when the iPhone app is newer than the watch app"))
        case .noAccounts:
            Unavailable(
                title: Text("No Accounts", tableName: "Wrist", bundle: .module, comment: "Shown with no mail accounts"),
                symbol: "envelope",
                description: Text(
                    "Add a mail account in Goodmail on your iPhone.", tableName: "Wrist", bundle: .module,
                    comment: "Shown with no mail accounts"))
        case .caughtUp:
            ScrollView {
                Unavailable(
                    title: Text(
                        "All Caught Up", tableName: "Wrist", bundle: .module, comment: "Shown when the Inbox is empty"),
                    symbol: "tray",
                    description: Text(
                        "Nothing in your Inbox.", tableName: "Wrist", bundle: .module,
                        comment: "Shown when the Inbox is empty"))
                if let freshness = model.freshness { WristFreshnessFooter(freshness: freshness) }
            }
        case .list(let snapshot):
            WristInboxList(snapshot: snapshot, model: model, threads: threads)
        }
    }
}

/// Why the Inbox shows no conversations.
private struct Unavailable: View {
    let title: Text
    let symbol: String
    let description: Text

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: symbol)
            }
        } description: {
            description
        }
    }
}
