#if DEBUG
    import Foundation
    import MailCore
    import MailWrist
    import MailWristUI

    /// Made-up mail without an iPhone, for screenshots.
    ///
    /// - `-GoodmailWristSample en` (or `he`) shows the sample Inbox.
    /// - `-GoodmailWristSampleOpen YES` opens its first conversation.
    /// - `-GoodmailWristSampleState <state>` shows the sample as the watch reads its Gmail account itself (ADR-023),
    ///   in one of `SampleState`'s states.
    enum WatchSample {
        /// Shows the sample when it was asked for; `false` when it wasn't.
        static func showIfRequested(inbox: WristInboxModel, threads: WristThreads, route: WristRoute) -> Bool {
            guard
                let language = UserDefaults.standard.string(forKey: "GoodmailWristSample")
                    .flatMap(WristSnapshot.SampleLanguage.init)
            else { return false }
            let state = UserDefaults.standard.string(forKey: "GoodmailWristSampleState").flatMap(SampleState.init)
            var sample = WristSnapshot.sample(language)
            if state == .needsIPhone { sample.madeAt = .now.addingTimeInterval(-45 * 60) }
            // The iPhone's pins, which it lays over the rows the watch reads itself.
            if state != nil { sample.extras = WristExtras(pinned: Set(sample.rows.filter(\.isPinned).map(\.id))) }
            // Few enough rows that what the state shows fits the first screen: the footer under one row, or the
            // iPhone's rows, which say they need it, first.
            switch state {
            case .updated, .checking, .offline, .signIn: sample.rows = Array(sample.rows.prefix(1))
            case .needsIPhone: sample.rows = sample.rows.filter { !$0.isPinned }
            case .tryAgain, .phoneAway, nil: break
            }
            inbox.receive(.snapshot(sample))
            if state?.opensUnloaded != true {
                for thread in WristThread.samples(for: sample, language) { threads.receive(.thread(thread)) }
            }
            if let state { state.show(sample, inbox: inbox, threads: threads, route: route) }
            if UserDefaults.standard.bool(forKey: "GoodmailWristSampleOpen"), let first = sample.rows.first {
                route.open(first.id)
            }
            return true
        }
    }

    /// How the sample shows the mail the watch reads itself: its Gmail account direct, its iCloud account relayed.
    enum SampleState: String {
        /// "Updated 2 min ago".
        case updated
        /// "Checking for Mail…".
        case checking
        /// "Can't Check Mail", offline.
        case offline
        /// "Can't Check Mail", the sign-in was turned down.
        case signIn
        /// The iPhone has been quiet for 45 minutes: the iCloud rows say "Needs iPhone".
        case needsIPhone
        /// A direct conversation that couldn't be fetched, with Try Again.
        case tryAgain
        /// A relayed conversation the iPhone didn't send, which says "Needs iPhone" after the wait.
        case phoneAway

        /// Whether the conversation it opens starts unloaded, to show how loading it ends.
        var opensUnloaded: Bool { self == .tryAgain || self == .phoneAway }

        func show(_ sample: WristSnapshot, inbox: WristInboxModel, threads: WristThreads, route: WristRoute) {
            guard let direct = sample.accounts.first(where: { $0.service == .gmail })?.id else { return }
            let sources = Dictionary(
                uniqueKeysWithValues: sample.accounts.map { account in
                    (account.id, account.id == direct ? WristAccountSource.direct : .relayed(.service))
                })
            var own = sample
            own.madeAt = .now
            own.rows = sample.rows.filter { $0.id.accountID == direct }
            inbox.receiveOwn(own, sources: sources)
            switch self {
            case .updated, .needsIPhone: inbox.freshness = .current(checkedAt: .now.addingTimeInterval(-120))
            case .checking: inbox.freshness = .checking(lastChecked: .now.addingTimeInterval(-600))
            case .offline: inbox.freshness = .behind(.offline, lastChecked: .now.addingTimeInterval(-3_600))
            case .signIn: inbox.freshness = .behind(.signInFailed, lastChecked: nil)
            case .tryAgain:
                threads.readDirectly([direct]) { _ in throw URLError(.notConnectedToInternet) }
                if let row = sample.rows.first(where: { $0.id.accountID == direct }) { route.open(row.id) }
            case .phoneAway:
                if let row = sample.rows.first(where: { $0.id.accountID != direct }) { route.open(row.id) }
            }
        }
    }
#endif
