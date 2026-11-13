import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct MailboxTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        return calendar
    }()

    /// Wednesday, 21 October 2026, 15:00 UTC.
    private var now: Date { date(2026, 10, 21, 15) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func section(_ date: Date) -> TimeSection {
        TimeSection.section(for: date, now: now, calendar: calendar)
    }

    @Test func todaySplitsIntoMorningAfternoonAndEvening() {
        #expect(section(date(2026, 10, 21, 8)) == .thisMorning)
        #expect(section(date(2026, 10, 21, 13)) == .thisAfternoon)
        #expect(section(date(2026, 10, 21, 0)) == .thisMorning)
        let evening = TimeSection.section(for: date(2026, 10, 21, 19), now: date(2026, 10, 21, 22), calendar: calendar)
        #expect(evening == .thisEvening)
    }

    @Test func mailFromTheNearFutureCountsAsNow() {
        #expect(section(date(2026, 10, 21, 18)) == .thisAfternoon, "clock skew must not jump a thread to evening")
    }

    @Test func olderMailFallsIntoCalendarBuckets() {
        #expect(section(date(2026, 10, 20, 23)) == .yesterday)
        #expect(section(date(2026, 10, 18)) == .thisWeek, "Sunday starts this week")
        #expect(section(date(2026, 10, 17)) == .lastWeek)
        #expect(section(date(2026, 10, 11)) == .lastWeek)
        #expect(section(date(2026, 10, 3)) == .thisMonth)
        #expect(section(date(2026, 9, 30)) == .month(year: 2026, month: 9))
        #expect(section(date(2025, 12, 31)) == .month(year: 2025, month: 12))
    }

    @Test func monthTitlesAddTheYearOnlyForPastYears() {
        #expect(TimeSection.month(year: 2026, month: 9).title(now: now, calendar: calendar) == "September")
        #expect(TimeSection.month(year: 2025, month: 12).title(now: now, calendar: calendar) == "December 2025")
    }

    @Test func groupingKeepsOrderAndMergesRuns() {
        let dates = [date(2026, 10, 21, 9), date(2026, 10, 21, 8), date(2026, 10, 20), date(2026, 9, 1)]
        let groups = TimeSection.group(dates, by: \.self, now: now, calendar: calendar)
        #expect(groups.map(\.section) == [.thisMorning, .yesterday, .month(year: 2026, month: 9)])
        #expect(groups.map(\.items.count) == [2, 1, 1])
    }

    @Test func rowDateShowsTimeThenWeekdayThenDate() {
        #expect(RowDate.text(for: date(2026, 10, 21, 9), now: now, calendar: calendar) == "9:00\u{202F}AM")
        #expect(RowDate.text(for: date(2026, 10, 16), now: now, calendar: calendar) == "Fri")
        #expect(RowDate.text(for: date(2026, 10, 1), now: now, calendar: calendar) == "Oct 1")
        #expect(RowDate.text(for: date(2025, 10, 1), now: now, calendar: calendar) == "Oct 1, 2025")
    }

    @Test func monogramsTakeTwoInitialsInAnyScript() {
        #expect(Monogram.initials(for: "Dana Levi") == "DL")
        #expect(Monogram.initials(for: "יעל כהן") == "יכ")
        #expect(Monogram.initials(for: "\"Ann\" Marie Smith") == "AM")
        #expect(Monogram.initials(for: "noreply@shop.example") == "NS")
        #expect(Monogram.initials(for: "") == "")
    }

    @Test func viewModelGroupsTheStoreIntoTitledSections() async {
        let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal)
        let threads = [date(2026, 10, 21, 9), date(2026, 10, 20)].enumerated().map { index, date in
            ThreadSummary(
                id: ThreadSummary.ID(accountID: account.id, threadID: "\(index)"),
                subject: "", snippet: "", sender: Contact(name: nil, address: "x@example.com"),
                date: date, isUnread: false, messageCount: 1, labelIDs: ["INBOX"]
            )
        }
        let viewModel = MailboxViewModel(
            accounts: [account],
            source: .flat {
                AsyncThrowingStream {
                    $0.yield(threads)
                    $0.finish()
                }
            },
            refresh: {},
            now: { [now] in now },
            calendar: calendar
        )
        await viewModel.observe()

        #expect(viewModel.sections.map(\.title) == ["This morning", "Yesterday"])
        #expect(viewModel.sections.map { $0.threads.map(\.id.threadID) } == [["0"], ["1"]])
        #expect(viewModel.theme == .account(.teal))
    }

    @Test func refreshFailureIsKeptUntilTheNextSuccess() async {
        struct Offline: Error {}
        var fail = true
        let viewModel = MailboxViewModel(
            accounts: [],
            source: .flat { AsyncThrowingStream { $0.finish() } },
            refresh: { if fail { throw Offline() } }
        )
        await viewModel.refresh()
        #expect(viewModel.refreshError is Offline)
        #expect(!viewModel.isRefreshing)
        fail = false
        await viewModel.refresh()
        #expect(viewModel.refreshError == nil)
    }

    @Test func loadingOlderStopsOnceTheProviderRunsOutAndRetriesAfterAFailure() async {
        struct Offline: Error {}
        var calls = 0
        var replies: [Result<Bool, any Error>] = [.failure(Offline()), .success(true), .success(false)]
        let viewModel = MailboxViewModel(
            accounts: [],
            source: .flat { AsyncThrowingStream { $0.finish() } },
            refresh: {},
            loadOlder: {
                calls += 1
                return try replies.removeFirst().get()
            }
        )
        await viewModel.loadOlderIfNeeded()
        await viewModel.loadOlderIfNeeded()
        await viewModel.loadOlderIfNeeded()
        await viewModel.loadOlderIfNeeded()
        #expect(calls == 3, "failure retries, true continues, false stops")
        #expect(!viewModel.isLoadingOlder)
    }
}
