import Foundation
import MailCore
import Observation

/// One conversation: its messages, which of them are open as cards, and whose remote content the reader allowed.
@Observable
public final class ThreadViewModel {
    public let thread: ThreadSummary
    public let accountEmail: String
    public let accountColor: AccountColor
    public private(set) var messages: [Message] = []
    /// Messages shown as cards; the rest are one-line rows in the timeline.
    public private(set) var expanded: Set<Message.ID> = []
    public private(set) var remoteContentAllowed: Set<Message.ID> = []
    public private(set) var isLoading = false
    public private(set) var loadError: (any Error)?

    @ObservationIgnored private let stream: () -> AsyncThrowingStream<[Message], any Error>
    @ObservationIgnored private let loadAction: () async throws -> Void
    @ObservationIgnored let attachmentData: (Attachment, Message.ID) async throws -> Data
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(
        thread: ThreadSummary,
        accountEmail: String,
        accountColor: AccountColor,
        messages: @escaping () -> AsyncThrowingStream<[Message], any Error>,
        load: @escaping () async throws -> Void,
        attachmentData: @escaping (Attachment, Message.ID) async throws -> Data,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.thread = thread
        self.accountEmail = accountEmail
        self.accountColor = accountColor
        stream = messages
        loadAction = load
        self.attachmentData = attachmentData
        self.now = now
        self.calendar = calendar
    }

    /// Shows the cached messages at once, then fetches the latest; follows the store until cancelled.
    public func observe() async {
        Task { await load() }
        do {
            for try await messages in stream() {
                if expanded.isEmpty { expanded = Self.initiallyExpanded(messages) }
                self.messages = messages
            }
        } catch {
            loadError = error
        }
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
}
