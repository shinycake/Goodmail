import Foundation
import MailCore
import Observation

/// One conversation: its messages, which of them are open as cards, and whose remote content the reader allowed.
@Observable
public final class ThreadViewModel {
    public let thread: ThreadSummary
    /// The mailbox the reader opened the thread from, which a move takes it out of.
    public let mailbox: Mailbox
    public let accountEmail: String
    public let accountColor: AccountColor
    /// The account's service, which decides the actions it has, such as Mute.
    public let accountService: MailService
    public private(set) var messages: [Message] = []
    /// Messages shown as cards; the rest are one-line rows in the timeline.
    public private(set) var expanded: Set<Message.ID> = []
    public private(set) var remoteContentAllowed: Set<Message.ID> = []
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
    /// The messages as chat bubbles, worked out off the main actor each time they change.
    public private(set) var transcript: ChatTranscript

    @ObservationIgnored private let stream: () -> AsyncThrowingStream<[Message], any Error>
    @ObservationIgnored private let loadAction: () async throws -> Void
    @ObservationIgnored let attachmentData: (Attachment, Message.ID) async throws -> Data
    @ObservationIgnored private let actions: MailActions?
    @ObservationIgnored private let navigate: (Route) -> Void
    @ObservationIgnored private let close: () -> Void
    @ObservationIgnored private var hasMarkedRead = false
    @ObservationIgnored private let attachmentsDirectory: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(
        thread: ThreadSummary,
        mailbox: Mailbox,
        accountEmail: String,
        accountColor: AccountColor,
        accountService: MailService,
        messages: @escaping () -> AsyncThrowingStream<[Message], any Error>,
        load: @escaping () async throws -> Void,
        attachmentData: @escaping (Attachment, Message.ID) async throws -> Data,
        actions: MailActions? = nil,
        navigate: @escaping (Route) -> Void = { _ in },
        close: @escaping () -> Void = {},
        attachmentsDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "Attachments"),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        layout: ConversationLayout = Preferences.conversationLayout
    ) {
        self.layout = layout
        transcript = ChatTranscript(messages: [], accountEmail: accountEmail)
        self.actions = actions
        self.navigate = navigate
        self.close = close
        self.attachmentsDirectory = attachmentsDirectory
        self.thread = thread
        self.mailbox = mailbox
        self.accountEmail = accountEmail
        self.accountColor = accountColor
        self.accountService = accountService
        stream = messages
        loadAction = load
        self.attachmentData = attachmentData
        self.now = now
        self.calendar = calendar
    }

    /// Shows the cached messages at once, then fetches the latest; follows the store until cancelled. Opening a
    /// thread reads it.
    public func observe() async {
        if thread.isUnread, !hasMarkedRead {
            hasMarkedRead = true
            actions?.perform(.markRead(true), on: [thread.id])
        }
        // A child of the observation, so leaving the thread cancels the fetch with it.
        async let loading: Void = load()
        do {
            for try await messages in stream() {
                if expanded.isEmpty { expanded = Self.initiallyExpanded(messages) }
                let transcript = await Self.transcript(of: messages, accountEmail: accountEmail)
                self.messages = messages
                self.transcript = transcript
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
    nonisolated static func transcript(of messages: [Message], accountEmail: String) async -> ChatTranscript {
        ChatTranscript(messages: messages, accountEmail: accountEmail)
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

    public func allowRemoteContent(in id: Message.ID) {
        remoteContentAllowed.insert(id)
    }

    /// A local copy of an attachment for Quick Look, named as the sender named it. Fetched once per message part.
    /// Each use stamps the file's modification date: the cache cap evicts the least recently used first.
    public func file(for attachment: Attachment, in message: Message.ID) async throws -> URL {
        let folder =
            attachmentsDirectory
            .appending(path: message.accountID.rawValue, directoryHint: .isDirectory)
            .appending(path: "\(message.messageID)-\(attachment.id)", directoryHint: .isDirectory)
        let url = folder.appending(path: Self.safeFilename(attachment.filename))
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.setAttributes(
                [.modificationDate: now()], ofItemAtPath: url.path(percentEncoded: false))
            return url
        }
        let data = try await attachmentData(attachment, message)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Path separators and leading dots can't escape the folder or hide the file.
    static func safeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return cleaned.isEmpty ? "Attachment" : cleaned
    }

    /// Whether any message carries the star; the toolbar's star button toggles it for the thread.
    public var isStarred: Bool {
        messages.contains { $0.labelIDs.contains(SystemLabel.starred) }
    }

    /// Mute or Unmute for the thread as it stands now, when it applies.
    public var muteAction: ThreadAction? {
        let labels = messages.reduce(into: Set<String>()) { $0.formUnion($1.labelIDs) }
        return ThreadAction.muting([(messages.isEmpty ? thread.labelIDs : labels, accountService)])
    }

    /// Applies an action to the whole thread. Archive, Trash, Spam and Mute take it out of the mailbox, and Unread
    /// puts it back for later, so the reader leaves after them.
    public func perform(_ action: ThreadAction) {
        actions?.perform(action, on: [thread.id])
        if [.archive, .trash, .reportSpam, .mute, .markRead(false)].contains(action) { leave() }
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

    /// Replies to the newest message.
    public func reply(all: Bool) {
        guard let message = latestSent else { return }
        navigate(.compose(Draft.reply(to: message, all: all, accountEmail: accountEmail, wording: .localized)))
    }

    /// Sends a reply typed in the chat's field: to everyone on the newest message, like a reply in a group chat.
    public func sendChatReply(_ text: String, attachments: [DraftAttachment]) {
        guard let reply = chatReply(text, attachments: attachments) else { return }
        actions?.send(reply)
    }

    /// The chat reply as a draft: each line its own `dir=auto` paragraph, so Hebrew and English lines each read
    /// their own way in any client. `nil` while there is no sent message to answer.
    func chatReply(_ text: String, attachments: [DraftAttachment]) -> Draft? {
        guard let message = latestSent else { return nil }
        var reply = Draft.reply(to: message, all: true, accountEmail: accountEmail)
        let paragraphs = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.isEmpty ? "<div dir=\"auto\"><br></div>" : "<div dir=\"auto\">\(HTMLText.escape(String(line)))</div>"
        }
        reply.body = MessageBody(html: paragraphs.joined(), plain: text)
        reply.attachments = attachments
        return reply
    }

    public func forward() {
        guard let message = latestSent else { return }
        navigate(.compose(Draft.forward(message, wording: .localized)))
    }

    /// The newest message when it is a draft not yet sent, which the reader finishes rather than answers.
    public var draft: Message? {
        messages.last.flatMap { $0.labelIDs.contains(SystemLabel.draft) ? $0 : nil }
    }

    public func editDraft() {
        guard let draft else { return }
        navigate(.compose(Draft.editing(draft)))
    }

    /// Replies and forwards answer the newest message that went, never an unsent draft.
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
