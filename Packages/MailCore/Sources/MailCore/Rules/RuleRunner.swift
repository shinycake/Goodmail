public import Foundation

/// What running rules needs from the store. `MailStore` implements it; tests use the real store.
public protocol RuleStore: PrefetchStore {
    /// Every rule, in the order they run.
    func rules() throws -> [MailRule]
    /// The account's conversations whose newest message arrived since the last claim, outside Spam, Trash and
    /// Drafts, oldest first, at most `limit`, recorded as claimed in the same transaction, so two processes catching
    /// up on the same mail run the rules on it once. The first claim for an account claims nothing and starts from
    /// `now`, so rules never run on mail that was there before. "Arrived" goes by the message's date, so mail that
    /// reaches the account with a date older than the last claim, as a delayed delivery can, isn't claimed.
    func claimRuleMail(in account: AccountID, now: Date, limit: Int) throws -> [ThreadSummary.ID]
    /// The cached messages of the threads, newest first.
    func messageFacts(inThreads ids: [ThreadSummary.ID], mailboxNames: [String: String]) throws -> [MailFacts]
    /// The threads as their list rows show them, newest first.
    func threadFacts(_ ids: [ThreadSummary.ID], mailboxNames: [String: String]) throws -> [MailFacts]
    func labels(for account: AccountID) throws -> [MailLabel]
}

/// A notification a rule asked for (`RuleAction.notify`).
public struct RuleAlert: Equatable, Sendable {
    public var keyword: String
    public var rule: String
    public var thread: ThreadSummary.ID
    public var sender: Contact
    public var subject: String
}

/// What one run of the rules did that its caller acts on: the notifications the rules asked for, to post, and the
/// actions that failed, to log. A failed action doesn't stop the others; the mail it was for has been claimed, so it
/// isn't tried again.
public struct RuleRun: Sendable {
    /// An action that couldn't be applied to a conversation.
    public struct Failure: Sendable {
        public var rule: String
        public var thread: ThreadSummary.ID
        public var error: any Error
    }

    public var alerts: [RuleAlert] = []
    public var failures: [Failure] = []
}

/// Runs the rules on an account's newly arrived mail: once per conversation that a new message arrived in, judged by
/// that message, and only for mail others sent. Called after each sync, in the app and in the notification
/// extension, whichever gets the mail first.
public struct RuleRunner: Sendable {
    /// The most conversations one run takes, so a flood of mail doesn't keep a short-lived process busy. The newer
    /// rest wait for the next run.
    public static let claimLimit = 50

    private let store: any RuleStore
    private let provider: any MailProvider
    private let commands: MailCommands
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        store: any RuleStore,
        provider: any MailProvider,
        commands: MailCommands,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.provider = provider
        self.commands = commands
        self.calendar = calendar
        self.now = now
    }

    /// Runs the rules on `account`'s new mail. Returns the notifications they asked for, for the caller to post, and
    /// the actions that failed. A message whose body can't be fetched is judged by what its list row shows. It
    /// throws only when the rules or the mail can't be read.
    @concurrent public func run(for account: AccountID) async throws -> RuleRun {
        let date = now()
        let book = RuleBook(try store.rules().filter(\.isEnabled))
        let labels = try store.labels(for: account)
        let claimed = try store.claimRuleMail(in: account, now: date, limit: Self.claimLimit)
        guard !claimed.isEmpty, !book.rules.isEmpty else { return RuleRun() }
        await fetchMissingBodies(of: claimed)
        let context = MailCondition.Context(now: date, calendar: calendar)
        var run = RuleRun()
        for facts in try newestFacts(of: claimed) where facts.flag(.fromMe) != true {
            let match = book.match(facts, in: context)
            let thread = facts.envelope.thread
            for action in match.actions {
                let rule = match.rules.first { $0.actions.contains(action) }?.name ?? ""
                do {
                    switch Step(action, labels: labels, in: facts.envelope.labelIDs, now: date) {
                    case .perform(let change): try await commands.perform(change, on: [thread])
                    case .snooze(let wake): try await commands.snooze([thread], until: wake)
                    case .pin: try await commands.pin([thread], true)
                    case .notify(let keyword):
                        run.alerts.append(
                            RuleAlert(
                                keyword: keyword, rule: rule, thread: thread, sender: facts.envelope.sender,
                                subject: facts.envelope.subject))
                    case .skip: continue
                    }
                } catch {
                    run.failures.append(RuleRun.Failure(rule: rule, thread: thread, error: error))
                }
            }
        }
        return run
    }

    /// Downloads the messages of the claimed threads that have none cached, a few at a time, so rules on what only
    /// a body tells (the CC list, the text, prices) can judge them. A failed fetch leaves the thread to its list row.
    private func fetchMissingBodies(of threads: [ThreadSummary.ID]) async {
        let cached = Set(
            ((try? store.messageFacts(inThreads: threads, mailboxNames: [:])) ?? []).map(\.envelope.thread))
        let missing = threads.filter { !cached.contains($0) }
        let (provider, store, fetchedAt) = (provider, store, now())
        await withTaskGroup(of: Void.self) { group in
            for thread in missing {
                group.addTask {
                    guard let messages = try? await provider.messages(inThread: thread.threadID) else { return }
                    try? store.savePrefetched(messages, inThread: thread, fetchedAt: fetchedAt)
                }
            }
        }
    }

    /// Each thread's newest cached message, or its list row when none is cached.
    private func newestFacts(of threads: [ThreadSummary.ID]) throws -> [MailFacts] {
        var newest: [ThreadSummary.ID: MailFacts] = [:]
        for facts in try store.messageFacts(inThreads: threads, mailboxNames: [:])
        where newest[facts.envelope.thread] == nil {
            newest[facts.envelope.thread] = facts
        }
        let rows = try store.threadFacts(threads.filter { newest[$0] == nil }, mailboxNames: [:])
        for facts in rows { newest[facts.envelope.thread] = facts }
        return threads.compactMap { newest[$0] }
    }
}

/// How one rule action is carried out on a conversation.
enum Step: Equatable {
    case perform(ThreadAction)
    case snooze(until: Date)
    case pin
    case notify(String)
    /// A label the account doesn't have.
    case skip

    init(_ action: RuleAction, labels: [MailLabel], in current: Set<String>, now: Date) {
        switch action {
        case .markRead: self = .perform(.markRead(true))
        case .star: self = .perform(.star(true))
        case .markImportant: self = .perform(.modifyLabels(add: [SystemLabel.important], remove: []))
        case .archive: self = .perform(.archive)
        case .trash: self = .perform(.trash)
        case .reportSpam: self = .perform(.reportSpam)
        case .mute: self = .perform(.mute)
        case .pin: self = .pin
        case .snooze(let seconds): self = .snooze(until: now.addingTimeInterval(seconds))
        case .notify(let keyword): self = .notify(keyword)
        case .addLabel(let name):
            self = Self.label(named: name, in: labels).map { .perform(.modifyLabels(add: [$0], remove: [])) } ?? .skip
        case .move(let name):
            let source = current.contains(SystemLabel.inbox) ? Mailbox(labelID: SystemLabel.inbox) : .allMail
            self = Self.label(named: name, in: labels).map { .perform(.move(to: .label($0), from: source)) } ?? .skip
        }
    }

    /// The ID of the account's user label named `name`, ignoring case.
    private static func label(named name: String, in labels: [MailLabel]) -> String? {
        labels.first { $0.kind == .user && $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
    }
}
