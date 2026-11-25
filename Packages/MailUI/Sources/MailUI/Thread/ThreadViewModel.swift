public import Foundation
public import MailCore
public import Observation

/// One conversation: its messages, which of them are open as cards, and whose remote content the reader allowed.
@Observable
public final class ThreadViewModel {
    public let thread: ThreadSummary
    /// The mailbox the reader opened the thread from, which a move takes it out of.
    public let mailbox: Mailbox
    public let accountEmail: String
    /// The account's other addresses, which answers to mail sent to one go from.
    public let accountAliases: [Contact]
    public let accountColor: AccountColor
    /// What the reader has to show: nothing yet while it is fetched, its messages, or why it has none.
    public private(set) var content = ConversationContent.loading
    /// Its messages, while there are any to show.
    public var messages: [Message] { content.messages }
    /// Messages shown as cards; the rest are one-line rows in the timeline.
    public var expanded: Set<Message.ID> { cards.ids }
    /// Which messages are cards, decided once the conversation first shows its messages.
    private var cards = OpenCards.unset
    /// Messages whose remote content the reader loaded once.
    private var loadedOnce: Set<Message.ID> = []
    /// The rules that load remote images without asking, as of opening the thread and trusting from it.
    private var trustRules: [ImageTrustRule]
    /// How this conversation reads. It opens in the reader's chosen layout, and the toolbar switches it.
    public private(set) var layout: ConversationLayout
    /// The messages as chat bubbles, with my replies still on their way at the end, worked out off the main actor
    /// each time either changes.
    public private(set) var transcript: ChatTranscript
    /// My replies to this conversation still on their way, kept up to date as each change arrives; the transcript
    /// shows them.
    @ObservationIgnored private var pending = PendingReplies()
    /// My replies on their way, as `transcript` last showed them, for the classic layout to show as letters.
    /// `pending` runs ahead of it while a transcript is being worked out.
    public private(set) var replies: [PendingReply] = []
    /// When `pending` was last worked out, which its deliveries hold for.
    @ObservationIgnored private var transcriptDate = Date.distantPast
    /// Whether the thread is pinned to the top of its lists.
    public private(set) var isPinned = false

    @ObservationIgnored private let stream: () -> AsyncThrowingStream<[Message], any Error>
    @ObservationIgnored private let pins: () -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>
    @ObservationIgnored private let outgoing: () -> AsyncThrowingStream<[OutgoingMessage], any Error>
    /// The conversation's messages and outgoing queue as last read; `messages` shows them once the transcript is
    /// worked out.
    @ObservationIgnored private var received: [Message] = []
    @ObservationIgnored private var queue: [OutgoingMessage] = []
    /// The transcript being worked out, so one worked out for older messages or an older queue never replaces a newer
    /// one.
    @ObservationIgnored private var transcriptWork = TranscriptWork.idle
    @ObservationIgnored private let loadAction: () async throws -> Void
    @ObservationIgnored let attachmentData: (Attachment, Message.ID) async throws -> Data
    /// A message's raw RFC 5322 source, for sharing it as an `.eml` file or `.mbox` archive.
    @ObservationIgnored let source: (Message.ID) async throws -> Data
    /// The window's actions, which tell it of each change asked here, so the window moves the reader (R7).
    @ObservationIgnored let actions: MailActions?
    /// Apply Rules, Block Sender and VIPs, where the app offers them.
    @ObservationIgnored let senders: SenderRules?
    @ObservationIgnored private let navigate: (Route) -> Void
    /// The labels the store's row of the thread carries, `nil` while it isn't on the device.
    @ObservationIgnored private let storedLabels: () -> AsyncThrowingStream<Set<String>?, any Error>
    /// Told whether the mailbox the thread is read in holds it, as the reader opens and each time that changes, as when
    /// another device, an alert action or a rule takes it out; the window decides whether the reader goes
    /// (`WindowNavigation.Event.placed`).
    @ObservationIgnored private let placed: (_ inMailbox: Bool) -> Void
    /// Whether opening still owes the thread its read mark: an unread thread's first observation marks it, once.
    @ObservationIgnored private var owesReadMark: Bool
    @ObservationIgnored private let attachmentsDirectory: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let imageTrust: ImageTrustRules

    public init(
        thread: ThreadSummary,
        mailbox: Mailbox,
        accountEmail: String,
        accountAliases: [Contact] = [],
        accountColor: AccountColor,
        messages: @escaping () -> AsyncThrowingStream<[Message], any Error>,
        pins: @escaping () -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error> = {
            AsyncThrowingStream { $0.finish() }
        },
        outgoing: @escaping () -> AsyncThrowingStream<[OutgoingMessage], any Error> = {
            AsyncThrowingStream { $0.finish() }
        },
        load: @escaping () async throws -> Void,
        attachmentData: @escaping (Attachment, Message.ID) async throws -> Data,
        source: @escaping (Message.ID) async throws -> Data,
        actions: MailActions? = nil,
        senders: SenderRules? = nil,
        navigate: @escaping (Route) -> Void = { _ in },
        storedLabels: @escaping () -> AsyncThrowingStream<Set<String>?, any Error> = {
            AsyncThrowingStream { $0.finish() }
        },
        placed: @escaping (_ inMailbox: Bool) -> Void = { _ in },
        attachmentsDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "Attachments"),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        layout: ConversationLayout = Preferences.conversationLayout,
        imageTrust: ImageTrustRules = ImageTrustRules()
    ) {
        self.imageTrust = imageTrust
        owesReadMark = thread.isUnread
        trustRules = imageTrust.all
        self.layout = layout
        transcript = ChatTranscript(messages: [], accountEmail: accountEmail, aliases: accountAliases)
        self.actions = actions
        self.senders = senders
        self.navigate = navigate
        self.storedLabels = storedLabels
        self.placed = placed
        self.attachmentsDirectory = attachmentsDirectory
        self.thread = thread
        self.mailbox = mailbox
        self.accountEmail = accountEmail
        self.accountAliases = accountAliases
        self.accountColor = accountColor
        stream = messages
        self.pins = pins
        self.outgoing = outgoing
        loadAction = load
        self.attachmentData = attachmentData
        self.source = source
        self.now = now
        self.calendar = calendar
    }

    /// Shows the cached messages at once, then fetches the latest; follows the store until cancelled. Opening a
    /// thread reads it. Only the window moves the reader: for what the reader asked here (R6–R8), or once the store shows
    /// the thread out of the mailbox it is read in (`placed`).
    public func observe() async {
        if owesReadMark {
            owesReadMark = false
            actions?.markOpened([thread.id])
        }
        // Children of the observation, so leaving the thread cancels the fetch and the pins with it.
        async let loading: Void = load()
        async let pinning: Void = followPins()
        async let sending: Void = followQueue()
        async let placing: Void = followPlace()
        do {
            for try await messages in stream() {
                // Before any transcript is worked out, which a later, already-read emission may overtake.
                cards.arrived(messages)
                received = messages
                await updateTranscript()
            }
        } catch {
            // The store couldn't be read: as a fetch that failed, it says so only with nothing to show.
            content.fetched(.failed)
        }
        await loading
        await pinning
        await sending
        await placing
    }

    /// Tells the window whether the mailbox the thread is read in holds it, by the labels of its row, which sync keeps
    /// up to date, rather than its messages', which change only when they are fetched again. Only changes are told, so
    /// other changes to its labels never undo what the reader's own change kept (R8). A thread not on the device, as a
    /// search result from the server, says nothing.
    private func followPlace() async {
        var told: Bool?
        do {
            for try await labels in storedLabels() {
                guard let labels else { continue }
                let inMailbox = mailbox.contains(labels: labels)
                guard inMailbox != told else { continue }
                told = inMailbox
                placed(inMailbox)
            }
        } catch {}
    }

    /// Follows the replies queued in this conversation, so each shows as a bubble from the moment it is sent.
    private func followQueue() async {
        await withDiscardingTaskGroup { group in
            // The clock matters only while there's a queue to follow, and stops with it.
            group.addTask { await self.followClock() }
            do {
                for try await queue in outgoing() {
                    self.queue = queue
                    await updateTranscript()
                }
            } catch {}
            group.cancelAll()
        }
    }

    /// Updates the transcript when a reply's delivery changes with the time: when its scheduled time comes, or when it
    /// is overdue and shows as still sending. Looked at each second, so a reply queued meanwhile is never missed.
    private func followClock() async {
        while (try? await Task.sleep(for: .seconds(1))) != nil {
            guard let next = pending.nextChange(after: transcriptDate), next <= now() else { continue }
            await updateTranscript()
        }
    }

    /// Works out the pending replies from what was received, then the transcript off the main actor, and shows
    /// them with the messages at once, unless a newer request overtook this one meanwhile.
    private func updateTranscript() async {
        let messages = received
        transcriptDate = now()
        pending.update(
            queue: queue, takenBack: actions?.takenBack ?? [], conversation: messages, accountEmail: accountEmail,
            now: transcriptDate)
        // A reply's synced copy opens as its card did, rather than folding into a row.
        let request = transcriptWork.start(copies: Set(pending.copies))
        let replies = pending.replies
        let transcript = await Self.transcript(
            of: messages, accountEmail: accountEmail, aliases: accountAliases, pending: replies)
        guard let copies = transcriptWork.finish(request) else { return }
        cards.open(copies)
        content.received(messages)
        self.transcript = transcript
        self.replies = replies
    }

    private func followPins() async {
        do {
            for try await pins in pins() { isPinned = pins.contains(thread.id) }
        } catch {}
    }

    /// Fetches the latest from the service, which the store then brings (`content`).
    public func load() async {
        content.refetching()
        do {
            try await loadAction()
            content.fetched(.done(stored: await stores()))
        } catch ProviderError.notFound {
            content.fetched(.notFound)
        } catch is CancellationError {
            // The reader went away; what it showed doesn't matter.
        } catch {
            content.fetched(.failed)
        }
    }

    /// Whether the store holds any of the conversation's messages now, as a fetch that just finished left it. A store
    /// that can't be read says nothing new, so what the reader has decides.
    private func stores() async -> Bool {
        do {
            for try await messages in stream() { return !messages.isEmpty }
        } catch {}
        return !received.isEmpty
    }

    /// Reading the bodies for their new words parses every message, so it stays off the main actor.
    @concurrent
    nonisolated static func transcript(
        of messages: [Message], accountEmail: String, aliases: [Contact], pending: [PendingReply]
    ) async -> ChatTranscript {
        ChatTranscript(messages: messages, accountEmail: accountEmail, aliases: aliases, pending: pending)
    }

    /// Reads this conversation the other way, without changing the layout others open in.
    public func switchLayout() {
        layout = layout.other
    }

    public func toggle(_ id: Message.ID) {
        cards.toggle(id)
    }

    /// The messages that may load remote content: those the reader loaded once, and every one a trust rule matches.
    public var remoteContentAllowed: Set<Message.ID> {
        Set(messages.lazy.filter(allowsRemoteContent).map(\.id))
    }

    public func allowsRemoteContent(in message: Message) -> Bool {
        loadedOnce.contains(message.id)
            || trustRules.trust(message.from.address)
    }

    public func allowRemoteContent(in id: Message.ID) {
        loadedOnce.insert(id)
    }

    /// Keeps `rule` on this device, one of `ImageTrustRule.offers(for:)` a message's sender, so remote images load
    /// in every message it matches, here and in threads opened later.
    public func alwaysAllowRemoteContent(by rule: ImageTrustRule) {
        imageTrust.add(rule)
        trustRules = imageTrust.all
    }

    /// A local copy of an attachment for Quick Look, named as the sender named it. Fetched once per message part;
    /// each use stamps the file, which the cache cap evicts by.
    public func file(for attachment: Attachment, in message: Message.ID) async throws -> URL {
        let files = AttachmentFiles(root: attachmentsDirectory)
        if let url = await files.cachedFile(for: attachment, in: message, at: now()) { return url }
        // A reply on its way has its files in its draft, not with the provider.
        if let draftData = replies.first(where: { $0.letterID == message })?.data(for: attachment) {
            return try await files.keep(draftData, for: attachment, in: message)
        }
        let data = try await attachmentData(attachment, message)
        // The fetch keeps the file it reads, unless the disk refused it.
        if let url = await files.cachedFile(for: attachment, in: message, at: now()) { return url }
        return try await files.keep(data, for: attachment, in: message)
    }

    /// Whether any message carries the star; the toolbar's star button toggles it for the thread.
    public var isStarred: Bool {
        messages.contains { $0.labelIDs.contains(SystemLabel.starred) }
    }

    /// The thread's labels as its messages carry them now, or as its row did while they load.
    public var labels: Set<String> {
        messages.isEmpty ? thread.labelIDs : messages.reduce(into: []) { $0.formUnion($1.labelIDs) }
    }

    /// Mute or Unmute for the thread as it stands now, when it applies.
    public var muteAction: ThreadAction? {
        ThreadAction.muting([labels])
    }

    /// Whether the thread was opened from Trash, so its toolbar deletes it forever instead of trashing it. Its labels
    /// can't say: a thread whose reply came in to the Inbox after its earlier messages were trashed carries Trash too.
    public var isInTrash: Bool { ThreadPlace(thread, in: mailbox) == .trash }

    /// Applies an action to the whole thread. The window decides from it where the reader goes (`MailActions.changed`).
    public func perform(_ action: ThreadAction) {
        actions?.perform(action, on: [thread.id])
    }

    /// Pins the thread to the top of its lists, or with `pinned` false unpins it. The reader stays.
    public func pin(_ pinned: Bool) {
        actions?.pin([thread.id], pinned)
    }

    /// Takes the thread out of the Inbox until `date`.
    public func snooze(until date: Date) {
        actions?.snooze([thread.id], until: date)
    }

    /// Opens the label picker for this thread.
    public func changeLabels() {
        navigate(.changeLabels([thread.id]))
    }

    /// Opens the places this thread can move to from its mailbox.
    public func move() {
        navigate(.move([thread.id], from: mailbox))
    }

    /// Opens the composer with `answer`'s draft: replies and forwards answer the newest message that went, never an
    /// unsent draft.
    public func answer(_ answer: Answer) {
        guard
            let draft = answer.draft(
                answering: messages, accountEmail: accountEmail, aliases: accountAliases, wording: .localized)
        else {
            return
        }
        navigate(.compose(draft))
    }

    /// Sends a reply typed in the chat's field, now or at `time`: to everyone on the newest message, like a reply
    /// in a group chat.
    public func sendChatReply(_ text: String, attachments: [DraftAttachment], at time: SendTime = .now) {
        guard let reply = chatReply(text, attachments: attachments) else { return }
        actions?.send(reply, at: time)
    }

    /// Opens the chat reply in the full composer, for formatting, recipients and drafts: the reply-all draft with
    /// its quote, carrying what was typed and attached so far.
    public func expandChatReply(_ text: String, attachments: [DraftAttachment]) {
        guard
            var draft = Answer.replyAll.draft(
                answering: messages, accountEmail: accountEmail, aliases: accountAliases, wording: .localized)
        else { return }
        if !text.isEmpty { draft.body = Self.chatBody(text) }
        draft.attachments += attachments
        navigate(.compose(draft))
    }

    /// Keeps a chat reply that was typed and never sent in Drafts as the reader goes, so nothing typed is lost.
    public func keepChatReply(_ text: String, attachments: [DraftAttachment]) {
        guard let reply = chatReply(text, attachments: attachments) else { return }
        actions?.saveDraft(reply, .leaving)
    }

    /// Opens a link in a message: a `mailto:` link as a new message from this account, in Goodmail, and any other
    /// link through `outside`.
    public func open(_ link: URL, outside: (URL) -> Void) {
        switch MessageLink(link, account: thread.id.accountID) {
        case .compose(let draft): navigate(.compose(draft))
        case .outside(let url): outside(url)
        }
    }

    /// Sends a reply that failed again.
    public func retry(_ id: Draft.ID) {
        guard let message = queued(id) else { return }
        actions?.retrySend(message)
    }

    /// Takes a failed or scheduled reply back into the composer.
    public func edit(_ id: Draft.ID) {
        guard let message = queued(id) else { return }
        if message.failure == nil { actions?.editScheduled(id) } else { actions?.discardSend(message, edit: true) }
    }

    /// Forgets a reply that failed.
    public func discard(_ id: Draft.ID) {
        guard let message = queued(id) else { return }
        actions?.discardSend(message)
    }

    /// Keeps a scheduled reply in Drafts instead of sending it.
    public func moveToDrafts(_ id: Draft.ID) {
        actions?.unschedule(id)
    }

    private func queued(_ id: Draft.ID) -> OutgoingMessage? {
        queue.first { $0.id == id }
    }

    /// The chat reply as a draft: each line its own `dir=auto` paragraph, so Hebrew and English lines each read
    /// their own way in any client. `nil` while there is no sent message to answer.
    func chatReply(_ text: String, attachments: [DraftAttachment]) -> Draft? {
        guard let message = latestSent else { return nil }
        var reply = Draft.reply(to: message, all: true, accountEmail: accountEmail, aliases: accountAliases)
        reply.body = Self.chatBody(text)
        reply.attachments = attachments
        return reply
    }

    /// Typed lines as a body, each its own `dir=auto` paragraph.
    static func chatBody(_ text: String) -> MessageBody {
        let paragraphs = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.isEmpty ? "<div dir=\"auto\"><br></div>" : "<div dir=\"auto\">\(HTMLText.escape(String(line)))</div>"
        }
        return MessageBody(html: paragraphs.joined(), plain: text)
    }

    /// The newest message when it is a draft not yet sent, which the reader finishes rather than answers.
    public var draft: Message? {
        messages.last.flatMap { $0.labelIDs.contains(SystemLabel.draft) ? $0 : nil }
    }

    public func editDraft() {
        guard let draft else { return }
        navigate(.compose(Draft.editing(draft, aliases: accountAliases)))
    }

    /// The chat answers the newest message that went, never an unsent draft.
    private var latestSent: Message? {
        messages.last { !$0.labelIDs.contains(SystemLabel.draft) }
    }

    /// The first message the view scrolls to: the first unread one, or the newest.
    public var firstFocused: Message.ID? {
        messages.first(where: \.isUnread)?.id ?? messages.last?.id
    }

    func dateText(for message: Message) -> String {
        RowDate.text(for: message.date, now: now(), calendar: calendar)
    }

    func timestampText(for date: Date) -> String {
        ChatTimestamp.text(for: date, now: now(), calendar: calendar)
    }
}

/// A chat timestamp: the time today, the weekday and time this past week, and the date and time before that.
nonisolated enum ChatTimestamp {
    static func text(for date: Date, now: Date, calendar: Calendar) -> String {
        let time = Date.FormatStyle(
            locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone
        ).hour().minute()
        let today = calendar.startOfDay(for: now)
        if calendar.isDate(date, inSameDayAs: today) { return date.formatted(time) }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: today), date >= weekAgo {
            return date.formatted(time.weekday(.wide))
        }
        if calendar.isDate(date, equalTo: today, toGranularity: .year) {
            return date.formatted(time.day().month(.abbreviated))
        }
        return date.formatted(time.day().month(.abbreviated).year())
    }
}
