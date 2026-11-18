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
    public private(set) var messages: [Message] = []
    /// Messages shown as cards; the rest are one-line rows in the timeline.
    public private(set) var expanded: Set<Message.ID> = []
    /// Messages whose remote content the reader loaded once.
    private var loadedOnce: Set<Message.ID> = []
    /// The rules that load remote images without asking, as of opening the thread and trusting from it.
    private var trustRules: [ImageTrustRule]
    public private(set) var isLoading = false
    public private(set) var loadError: (any Error)?
    /// Whether the reader is still on the thread. It leaves once, when an action or a move takes the thread out of
    /// `mailbox`, and closes then.
    public enum Presence: Equatable, Sendable {
        case reading
        case left
    }
    public private(set) var presence: Presence = .reading
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
    /// Synced copies of replies that left `pending`, to open as cards once a transcript shows them.
    @ObservationIgnored private var syncedCopies: Set<Message.ID> = []
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
    /// Counts transcript requests, so one worked out for older messages or an older queue never replaces a newer one.
    @ObservationIgnored private var transcriptRequest = 0
    @ObservationIgnored private let loadAction: () async throws -> Void
    @ObservationIgnored let attachmentData: (Attachment, Message.ID) async throws -> Data
    /// A message's raw RFC 5322 source, for sharing it as an `.eml` file or `.mbox` archive.
    @ObservationIgnored let source: (Message.ID) async throws -> Data
    @ObservationIgnored private let actions: MailActions?
    @ObservationIgnored private let navigate: (Route) -> Void
    @ObservationIgnored private let close: () -> Void
    @ObservationIgnored private var hasMarkedRead = false
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
        navigate: @escaping (Route) -> Void = { _ in },
        close: @escaping () -> Void = {},
        attachmentsDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "Attachments"),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        layout: ConversationLayout = Preferences.conversationLayout,
        imageTrust: ImageTrustRules = ImageTrustRules()
    ) {
        self.imageTrust = imageTrust
        trustRules = imageTrust.all
        self.layout = layout
        transcript = ChatTranscript(messages: [], accountEmail: accountEmail, aliases: accountAliases)
        self.actions = actions
        self.navigate = navigate
        self.close = close
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
    /// thread reads it.
    public func observe() async {
        if thread.isUnread, !hasMarkedRead {
            hasMarkedRead = true
            actions?.markOpened([thread.id])
        }
        // Children of the observation, so leaving the thread cancels the fetch and the pins with it.
        async let loading: Void = load()
        async let pinning: Void = followPins()
        async let sending: Void = followQueue()
        do {
            for try await messages in stream() {
                if expanded.isEmpty { expanded = Self.initiallyExpanded(messages) }
                received = messages
                await updateTranscript()
                if !messages.isEmpty, mailbox.contains(thread) {
                    var now = thread
                    now.labelIDs = messages.reduce(into: []) { $0.formUnion($1.labelIDs) }
                    if !mailbox.contains(now) { leave() }
                }
            }
        } catch {
            loadError = error
        }
        await loading
        await pinning
        await sending
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
        transcriptRequest += 1
        let request = transcriptRequest
        let messages = received
        transcriptDate = now()
        // A reply's synced copy opens as its card did, rather than folding into a row. Kept until a request is
        // shown, since `pending` forgets the reply now, before a newer request may overtake this one.
        syncedCopies.formUnion(pending.copies(in: messages))
        pending.update(
            queue: queue, takenBack: actions?.takenBack ?? [], conversation: messages, accountEmail: accountEmail,
            now: transcriptDate)
        let transcript = await Self.transcript(
            of: messages, accountEmail: accountEmail, aliases: accountAliases, pending: pending.replies)
        guard request == transcriptRequest else { return }
        expanded.formUnion(syncedCopies)
        syncedCopies = []
        self.messages = messages
        self.transcript = transcript
        replies = pending.replies
    }

    private func followPins() async {
        do {
            for try await pins in pins() { isPinned = pins.contains(thread.id) }
        } catch {}
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await loadAction()
            loadError = nil
        } catch {
            loadError = error
        }
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
        if expanded.contains(id), expanded.count > 1 {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
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

    /// Mute or Unmute for the thread as it stands now, when it applies.
    public var muteAction: ThreadAction? {
        let labels = messages.reduce(into: Set<String>()) { $0.formUnion($1.labelIDs) }
        return ThreadAction.muting([messages.isEmpty ? thread.labelIDs : labels])
    }

    /// Whether the thread was opened from Trash, so its toolbar deletes it forever instead of trashing it. Its labels
    /// can't say: a thread whose reply came in to the Inbox after its earlier messages were trashed carries Trash too.
    public var isInTrash: Bool { ThreadPlace(thread, in: mailbox) == .trash }

    /// Applies an action to the whole thread. Archive, Trash, Delete Forever, Spam and Mute take it out of the
    /// mailbox, and Unread puts it back for later, so the reader leaves after them.
    public func perform(_ action: ThreadAction) {
        actions?.perform(action, on: [thread.id])
        if [.archive, .trash, .deleteForever, .reportSpam, .mute, .markRead(false)].contains(action) { leave() }
    }

    /// Pins the thread to the top of its lists, or with `pinned` false unpins it. The reader stays.
    public func pin(_ pinned: Bool) {
        actions?.pin([thread.id], pinned)
    }

    /// Takes the thread out of the Inbox until `date`, and leaves it.
    public func snooze(until date: Date) {
        actions?.snooze([thread.id], until: date)
        leave()
    }

    /// The one transition out of the thread: the reader closes the first time, and never again.
    private func leave() {
        guard presence == .reading else { return }
        presence = .left
        close()
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

    /// Unread messages and the newest open as cards; the rest of the history stays in the timeline.
    static func initiallyExpanded(_ messages: [Message]) -> Set<Message.ID> {
        Set(messages.filter(\.isUnread).map(\.id) + (messages.last.map { [$0.id] } ?? []))
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
