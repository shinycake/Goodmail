public import AppIntents
import Foundation
public import MailCore

/// Finds cached messages by any of their details: Shortcuts' Find Messages and Filter actions, which Siri and the
/// Use Model action run too. Each comparison becomes a `MailCondition`, so the store reads only the dates asked for
/// and filters the rest in one pass.
///
/// The properties are spelled out one by one: Xcode reads them from the source to build the Find action.
public struct MessageQuery: EntityStringQuery, EntityPropertyQuery {
    public typealias ComparatorMappingType = MailCondition

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static let findIntentDescription: IntentDescription? = IntentDescription(
        LocalizedStringResource(
            "Finds mail on this device by its sender, recipients, dates, text, prices, labels or any other detail.",
            table: "ShortcutMail"))

    public static var properties: QueryProperties {
        QueryProperties {
            Property(\MessageEntity.$subject) {
                ContainsComparator { .text(.subject, .contains($0)) }
                EqualToComparator { .text(.subject, .equals($0 ?? "")) }
                NotEqualToComparator { .not(.text(.subject, .equals($0 ?? ""))) }
                HasPrefixComparator { .text(.subject, .beginsWith($0)) }
                HasSuffixComparator { .text(.subject, .endsWith($0)) }
            }
            Property(\MessageEntity.$body) {
                ContainsComparator { .text(.body, .contains($0)) }
                EqualToComparator { .text(.body, .equals($0 ?? "")) }
                HasPrefixComparator { .text(.body, .beginsWith($0)) }
                HasSuffixComparator { .text(.body, .endsWith($0)) }
            }
            Property(\MessageEntity.$snippet) {
                ContainsComparator { .text(.snippet, .contains($0)) }
            }
            Property(\MessageEntity.$from) {
                EqualToComparator { .text(.senderAddress, .equals($0.address)) }
                NotEqualToComparator { .not(.text(.senderAddress, .equals($0.address))) }
            }
            Property(\MessageEntity.$senderName) {
                EqualToComparator { .text(.senderName, .equals($0)) }
                NotEqualToComparator { .not(.text(.senderName, .equals($0))) }
                ContainsComparator { .text(.senderName, .contains($0)) }
                HasPrefixComparator { .text(.senderName, .beginsWith($0)) }
                HasSuffixComparator { .text(.senderName, .endsWith($0)) }
            }
            Property(\MessageEntity.$senderAddress) {
                EqualToComparator { .text(.senderAddress, .equals($0)) }
                NotEqualToComparator { .not(.text(.senderAddress, .equals($0))) }
                ContainsComparator { .text(.senderAddress, .contains($0)) }
                HasPrefixComparator { .text(.senderAddress, .beginsWith($0)) }
                HasSuffixComparator { .text(.senderAddress, .endsWith($0)) }
            }
            Property(\MessageEntity.$senderDomain) {
                EqualToComparator { .text(.senderDomain, .equals($0)) }
                NotEqualToComparator { .not(.text(.senderDomain, .equals($0))) }
                ContainsComparator { .text(.senderDomain, .contains($0)) }
                HasSuffixComparator { .text(.senderDomain, .endsWith($0)) }
            }
            Property(\MessageEntity.$recipientAddresses) {
                ContainsComparator { .text(.recipients, .equals($0)) }
            }
            Property(\MessageEntity.$replyToAddresses) {
                ContainsComparator { .text(.replyTo, .equals($0)) }
            }
            Property(\MessageEntity.$toCount) {
                EqualToComparator { .number(.toCount, .equals(Double($0))) }
                NotEqualToComparator { .not(.number(.toCount, .equals(Double($0)))) }
                LessThanComparator { .number(.toCount, .lessThan(Double($0))) }
                GreaterThanComparator { .number(.toCount, .greaterThan(Double($0))) }
                LessThanOrEqualToComparator { .number(.toCount, .atMost(Double($0))) }
                GreaterThanOrEqualToComparator { .number(.toCount, .atLeast(Double($0))) }
            }
            Property(\MessageEntity.$ccCount) {
                EqualToComparator { .number(.ccCount, .equals(Double($0))) }
                NotEqualToComparator { .not(.number(.ccCount, .equals(Double($0)))) }
                LessThanComparator { .number(.ccCount, .lessThan(Double($0))) }
                GreaterThanComparator { .number(.ccCount, .greaterThan(Double($0))) }
                LessThanOrEqualToComparator { .number(.ccCount, .atMost(Double($0))) }
                GreaterThanOrEqualToComparator { .number(.ccCount, .atLeast(Double($0))) }
            }
            Property(\MessageEntity.$bccCount) {
                EqualToComparator { .number(.bccCount, .equals(Double($0))) }
                NotEqualToComparator { .not(.number(.bccCount, .equals(Double($0)))) }
                LessThanComparator { .number(.bccCount, .lessThan(Double($0))) }
                GreaterThanComparator { .number(.bccCount, .greaterThan(Double($0))) }
                LessThanOrEqualToComparator { .number(.bccCount, .atMost(Double($0))) }
                GreaterThanOrEqualToComparator { .number(.bccCount, .atLeast(Double($0))) }
            }
            Property(\MessageEntity.$recipientCount) {
                EqualToComparator { .number(.recipientCount, .equals(Double($0))) }
                NotEqualToComparator { .not(.number(.recipientCount, .equals(Double($0)))) }
                LessThanComparator { .number(.recipientCount, .lessThan(Double($0))) }
                GreaterThanComparator { .number(.recipientCount, .greaterThan(Double($0))) }
                LessThanOrEqualToComparator { .number(.recipientCount, .atMost(Double($0))) }
                GreaterThanOrEqualToComparator { .number(.recipientCount, .atLeast(Double($0))) }
            }
            Property(\MessageEntity.$isFromMe) {
                EqualToComparator { .flag(.fromMe, $0) }
            }
            Property(\MessageEntity.$isToMe) {
                EqualToComparator { .flag(.toMe, $0) }
            }
            Property(\MessageEntity.$dateReceived) {
                LessThanComparator { .date(.date, .before($0)) }
                GreaterThanComparator { .date(.date, .after($0)) }
                IsBetweenComparator { .date(.date, .between($0, $1)) }
            }
            Property(\MessageEntity.$daysOld) {
                EqualToComparator { DaysOld.exactly($0) }
                NotEqualToComparator { .not(DaysOld.exactly($0)) }
                LessThanComparator { DaysOld.atMost($0 - 1) }
                GreaterThanComparator { DaysOld.atLeast($0 + 1) }
                LessThanOrEqualToComparator { DaysOld.atMost($0) }
                GreaterThanOrEqualToComparator { DaysOld.atLeast($0) }
                IsBetweenComparator { DaysOld.between($0, $1) }
            }
            Property(\MessageEntity.$weekday) {
                EqualToComparator { .weekday([$0.weekday]) }
                NotEqualToComparator { .not(.weekday([$0.weekday])) }
            }
            Property(\MessageEntity.$hour) {
                EqualToComparator { .timeOfDay(from: .hour($0), to: .hour($0 + 1)) }
                NotEqualToComparator { .not(.timeOfDay(from: .hour($0), to: .hour($0 + 1))) }
                LessThanComparator { .timeOfDay(from: .hour(0), to: .hour($0)) }
                GreaterThanComparator { .timeOfDay(from: .hour($0 + 1), to: .hour(24)) }
                LessThanOrEqualToComparator { .timeOfDay(from: .hour(0), to: .hour($0 + 1)) }
                GreaterThanOrEqualToComparator { .timeOfDay(from: .hour($0), to: .hour(24)) }
                IsBetweenComparator { .timeOfDay(from: .hour($0), to: .hour($1 + 1)) }
            }
            Property(\MessageEntity.$labels) {
                ContainsComparator { .text(.mailbox, .equals($0)) }
            }
            Property(\MessageEntity.$conversationLength) {
                EqualToComparator { .number(.messageCount, .equals(Double($0))) }
                LessThanComparator { .number(.messageCount, .lessThan(Double($0))) }
                GreaterThanComparator { .number(.messageCount, .greaterThan(Double($0))) }
                IsBetweenComparator { .number(.messageCount, .between(Double($0), Double($1))) }
            }
            Property(\MessageEntity.$totalAmount) {
                EqualToComparator { .number(.totalAmount, .equals($0 ?? 0)) }
                LessThanComparator { .number(.totalAmount, .lessThan($0)) }
                GreaterThanComparator { .number(.totalAmount, .greaterThan($0)) }
                LessThanOrEqualToComparator { .number(.totalAmount, .atMost($0)) }
                GreaterThanOrEqualToComparator { .number(.totalAmount, .atLeast($0)) }
                IsBetweenComparator { .number(.totalAmount, .between($0, $1)) }
            }
            Property(\MessageEntity.$largestAmount) {
                EqualToComparator { .number(.largestAmount, .equals($0 ?? 0)) }
                LessThanComparator { .number(.largestAmount, .lessThan($0)) }
                GreaterThanComparator { .number(.largestAmount, .greaterThan($0)) }
                LessThanOrEqualToComparator { .number(.largestAmount, .atMost($0)) }
                GreaterThanOrEqualToComparator { .number(.largestAmount, .atLeast($0)) }
                IsBetweenComparator { .number(.largestAmount, .between($0, $1)) }
            }
            Property(\MessageEntity.$isRead) {
                EqualToComparator { .flag(.unread, !$0) }
            }
            Property(\MessageEntity.$isFlagged) {
                EqualToComparator { .flag(.starred, $0) }
            }
            Property(\MessageEntity.$isImportant) {
                EqualToComparator { .flag(.important, $0) }
            }
            Property(\MessageEntity.$isInInbox) {
                EqualToComparator { .flag(.inInbox, $0) }
            }
            Property(\MessageEntity.$isArchived) {
                EqualToComparator { .flag(.archived, $0) }
            }
            Property(\MessageEntity.$isInTrash) {
                EqualToComparator { .flag(.inTrash, $0) }
            }
            Property(\MessageEntity.$isDraft) {
                EqualToComparator { .flag(.draft, $0) }
            }
            Property(\MessageEntity.$isReply) {
                EqualToComparator { .flag(.reply, $0) }
            }
            Property(\MessageEntity.$isForward) {
                EqualToComparator { .flag(.forward, $0) }
            }
            Property(\MessageEntity.$isPinned) {
                EqualToComparator { .flag(.pinned, $0) }
            }
            Property(\MessageEntity.$isMuted) {
                EqualToComparator { .flag(.muted, $0) }
            }
            Property(\MessageEntity.$isSnoozed) {
                EqualToComparator { .flag(.snoozed, $0) }
            }
            Property(\MessageEntity.$snoozedUntil) {
                LessThanComparator { .date(.snoozedUntil, .before($0)) }
                GreaterThanComparator { .date(.snoozedUntil, .after($0)) }
                IsBetweenComparator { .date(.snoozedUntil, .between($0, $1)) }
            }
            Property(\MessageEntity.$hasAttachments) {
                EqualToComparator { .flag(.hasAttachments, $0) }
            }
            Property(\MessageEntity.$attachmentCount) {
                EqualToComparator { .number(.attachmentCount, .equals(Double($0))) }
                LessThanComparator { .number(.attachmentCount, .lessThan(Double($0))) }
                GreaterThanComparator { .number(.attachmentCount, .greaterThan(Double($0))) }
                GreaterThanOrEqualToComparator { .number(.attachmentCount, .atLeast(Double($0))) }
            }
            Property(\MessageEntity.$attachmentNames) {
                ContainsComparator { .text(.attachmentName, .equals($0)) }
            }
            Property(\MessageEntity.$attachmentSize) {
                LessThanComparator { .number(.attachmentSize, .lessThan($0.bytes)) }
                GreaterThanComparator { .number(.attachmentSize, .greaterThan($0.bytes)) }
                IsBetweenComparator { .number(.attachmentSize, .between($0.bytes, $1.bytes)) }
            }
            Property(\MessageEntity.$hasUnsubscribe) {
                EqualToComparator { .flag(.hasUnsubscribe, $0) }
            }
        }

    }

    public static var sortingOptions: SortingOptions {
        SortingOptions {
            SortableBy(\MessageEntity.$dateReceived)
            SortableBy(\MessageEntity.$subject)
            SortableBy(\MessageEntity.$senderName)
            SortableBy(\MessageEntity.$totalAmount)
            SortableBy(\MessageEntity.$largestAmount)
            SortableBy(\MessageEntity.$recipientCount)
            SortableBy(\MessageEntity.$attachmentCount)
            SortableBy(\MessageEntity.$attachmentSize)
            SortableBy(\MessageEntity.$conversationLength)
        }

    }

    public func entities(
        matching comparators: [MailCondition], mode: ComparatorMode, sortedBy: [Sort<MessageEntity>], limit: Int?
    ) async throws -> [MessageEntity] {
        let condition: MailCondition = mode == .and ? .all(comparators) : .any(comparators)
        return try await Catalog(host: host).messages(
            matching: condition, sortedBy: sortedBy.compactMap(MailSort.init), limit: limit)
    }

    public func entities(for identifiers: [String]) async throws -> [MessageEntity] {
        try Catalog(host: host).messages(identifiers)
    }

    /// The cached messages of the conversations search finds.
    public func entities(matching string: String) async throws -> [MessageEntity] {
        try Catalog(host: host).threads(matching: string).flatMap(\.messages)
    }

    /// The cached messages of the newest conversations in the Inbox.
    public func suggestedEntities() async throws -> [MessageEntity] {
        try Catalog(host: host).recentThreads().flatMap(\.messages)
    }
}

extension MailSort {
    /// The order Shortcuts asks for, or `nil` for a property Find doesn't sort by.
    init?(_ sort: EntityQuerySort<MessageEntity>) {
        let keys: [(PartialKeyPath<MessageEntity>, Key)] = [
            (\MessageEntity.$dateReceived, .date), (\MessageEntity.$subject, .subject),
            (\MessageEntity.$senderName, .sender), (\MessageEntity.$totalAmount, .totalAmount),
            (\MessageEntity.$largestAmount, .largestAmount), (\MessageEntity.$recipientCount, .recipientCount),
            (\MessageEntity.$attachmentCount, .attachmentCount), (\MessageEntity.$attachmentSize, .attachmentSize),
            (\MessageEntity.$conversationLength, .messageCount),
        ]
        guard let key = keys.first(where: { $0.0 == sort.by })?.1 else { return nil }
        self.init(key, ascending: sort.order == .ascending)
    }
}

extension TimeOfDay {
    /// The start of `hour`; 24 is the end of the day.
    static func hour(_ hour: Int) -> TimeOfDay { TimeOfDay(hour: hour, minute: 0) }
}

extension Measurement where UnitType == UnitInformationStorage {
    var bytes: Double { converted(to: .bytes).value }
}
