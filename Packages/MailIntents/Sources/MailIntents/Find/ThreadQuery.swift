public import AppIntents
public import CoreSpotlight
public import MailCore

/// Finds conversations: Siri's and Spotlight's lookups, the pickers, and Shortcuts' Find Conversations and Filter
/// actions, which read every conversation stored, cached or only listed.
///
/// The properties are spelled out one by one: Xcode reads them from the source to build the Find action.
public struct ThreadQuery: EntityStringQuery, IndexedEntityQuery, EntityPropertyQuery {
    public typealias ComparatorMappingType = MailCondition

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static let findIntentDescription: IntentDescription? = IntentDescription(
        LocalizedStringResource(
            "Finds conversations on this device by their sender, date, labels or state.", table: "ShortcutMail"))

    public static var properties: QueryProperties {
        QueryProperties {
            Property(\ThreadEntity.$title) {
                ContainsComparator { .text(.subject, .contains($0)) }
                EqualToComparator { .text(.subject, .equals($0)) }
                NotEqualToComparator { .not(.text(.subject, .equals($0))) }
                HasPrefixComparator { .text(.subject, .beginsWith($0)) }
                HasSuffixComparator { .text(.subject, .endsWith($0)) }
            }
            Property(\ThreadEntity.$from) {
                EqualToComparator { .text(.senderAddress, .equals($0.address)) }
                NotEqualToComparator { .not(.text(.senderAddress, .equals($0.address))) }
            }
            Property(\ThreadEntity.$senderName) {
                EqualToComparator { .text(.senderName, .equals($0)) }
                ContainsComparator { .text(.senderName, .contains($0)) }
                HasPrefixComparator { .text(.senderName, .beginsWith($0)) }
            }
            Property(\ThreadEntity.$senderAddress) {
                EqualToComparator { .text(.senderAddress, .equals($0)) }
                NotEqualToComparator { .not(.text(.senderAddress, .equals($0))) }
                ContainsComparator { .text(.senderAddress, .contains($0)) }
                HasSuffixComparator { .text(.senderAddress, .endsWith($0)) }
            }
            Property(\ThreadEntity.$senderDomain) {
                EqualToComparator { .text(.senderDomain, .equals($0)) }
                NotEqualToComparator { .not(.text(.senderDomain, .equals($0))) }
                HasSuffixComparator { .text(.senderDomain, .endsWith($0)) }
            }
            Property(\ThreadEntity.$date) {
                LessThanComparator { .date(.date, .before($0)) }
                GreaterThanComparator { .date(.date, .after($0)) }
                IsBetweenComparator { .date(.date, .between($0, $1)) }
            }
            Property(\ThreadEntity.$daysOld) {
                EqualToComparator { DaysOld.exactly($0) }
                NotEqualToComparator { .not(DaysOld.exactly($0)) }
                LessThanComparator { DaysOld.atMost($0 - 1) }
                GreaterThanComparator { DaysOld.atLeast($0 + 1) }
                LessThanOrEqualToComparator { DaysOld.atMost($0) }
                GreaterThanOrEqualToComparator { DaysOld.atLeast($0) }
                IsBetweenComparator { DaysOld.between($0, $1) }
            }
            Property(\ThreadEntity.$messageCount) {
                EqualToComparator { .number(.messageCount, .equals(Double($0))) }
                LessThanComparator { .number(.messageCount, .lessThan(Double($0))) }
                GreaterThanComparator { .number(.messageCount, .greaterThan(Double($0))) }
                IsBetweenComparator { .number(.messageCount, .between(Double($0), Double($1))) }
            }
            Property(\ThreadEntity.$labels) {
                ContainsComparator { .text(.mailbox, .equals($0)) }
            }
            Property(\ThreadEntity.$accountAddress) {
                EqualToComparator { .text(.account, .equals($0)) }
            }
            Property(\ThreadEntity.$isUnread) {
                EqualToComparator { .flag(.unread, $0) }
            }
            Property(\ThreadEntity.$isStarred) {
                EqualToComparator { .flag(.starred, $0) }
            }
            Property(\ThreadEntity.$isImportant) {
                EqualToComparator { .flag(.important, $0) }
            }
            Property(\ThreadEntity.$isInInbox) {
                EqualToComparator { .flag(.inInbox, $0) }
            }
            Property(\ThreadEntity.$isArchived) {
                EqualToComparator { .flag(.archived, $0) }
            }
            Property(\ThreadEntity.$isInSpam) {
                EqualToComparator { .flag(.inSpam, $0) }
            }
            Property(\ThreadEntity.$isInTrash) {
                EqualToComparator { .flag(.inTrash, $0) }
            }
            Property(\ThreadEntity.$isPinned) {
                EqualToComparator { .flag(.pinned, $0) }
            }
            Property(\ThreadEntity.$isMuted) {
                EqualToComparator { .flag(.muted, $0) }
            }
            Property(\ThreadEntity.$isSnoozed) {
                EqualToComparator { .flag(.snoozed, $0) }
            }
            Property(\ThreadEntity.$snoozedUntil) {
                LessThanComparator { .date(.snoozedUntil, .before($0)) }
                GreaterThanComparator { .date(.snoozedUntil, .after($0)) }
                IsBetweenComparator { .date(.snoozedUntil, .between($0, $1)) }
            }
        }

    }

    public static var sortingOptions: SortingOptions {
        SortingOptions {
            SortableBy(\ThreadEntity.$date)
            SortableBy(\ThreadEntity.$title)
            SortableBy(\ThreadEntity.$senderName)
            SortableBy(\ThreadEntity.$messageCount)
        }

    }

    public func entities(
        matching comparators: [MailCondition], mode: ComparatorMode, sortedBy: [Sort<ThreadEntity>], limit: Int?
    ) async throws -> [ThreadEntity] {
        let condition: MailCondition = mode == .and ? .all(comparators) : .any(comparators)
        return try await Catalog(host: host).threads(
            matching: condition, sortedBy: sortedBy.compactMap(MailSort.init), limit: limit)
    }

    public func entities(for identifiers: [String]) async throws -> [ThreadEntity] {
        try await Catalog(host: host).threads(identifiers)
    }

    public func entities(matching string: String) async throws -> [ThreadEntity] {
        try await Catalog(host: host).threads(matching: string)
    }

    public func suggestedEntities() async throws -> [ThreadEntity] {
        try await Catalog(host: host).recentThreads()
    }

    /// Spotlight lost its copy: index the newest conversations again.
    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer(host: host).refresh()
    }

    public func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription)
        async throws
    {
        let threads = try await Catalog(host: host).threads(identifiers, withMessages: false)
        try await SystemSpotlightIndex().index(threads)
    }
}

extension MailSort {
    /// The order Shortcuts asks for, or `nil` for a property Find doesn't sort by.
    init?(_ sort: EntityQuerySort<ThreadEntity>) {
        let keys: [(PartialKeyPath<ThreadEntity>, Key)] = [
            (\ThreadEntity.$date, .date), (\ThreadEntity.$title, .subject), (\ThreadEntity.$senderName, .sender),
            (\ThreadEntity.$messageCount, .messageCount),
        ]
        guard let key = keys.first(where: { $0.0 == sort.by })?.1 else { return nil }
        self.init(key, ascending: sort.order == .ascending)
    }
}
