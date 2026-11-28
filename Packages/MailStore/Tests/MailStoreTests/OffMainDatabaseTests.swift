import Foundation
import MailCore
import Testing

@testable import MailStore

// Follows a store stream, so one that never emits fails the test instead of hanging the run.
@Suite(.timeLimit(.minutes(1)))
struct OffMainDatabaseTests {
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private var thread: ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t1"), subject: "Lunch?", snippet: "",
            sender: Contact(name: nil, address: "dana@example.com"), date: .now, isUnread: true, messageCount: 1,
            labelIDs: [SystemLabel.inbox])
    }

    private static func url() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "OffMainDatabaseTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
    }

    private struct Refused: Error, Equatable {}

    // Opening, reading and writing on the main actor would trap in Debug (`aReadOnTheMainActorTrapsInDebug`).
    @MainActor @Test func opensAndWorksOffTheMainActor() async throws {
        let database = try await OffMainDatabase.open(url: Self.url())
        let account = account
        let stored = try await database.offMain { database in
            try database.save(account)
            return try database.accounts()
        }
        #expect(stored == [account])
    }

    @Test func workThrowsItsOwnErrorType() async throws {
        let database = try await OffMainDatabase.open(url: Self.url())
        do throws(Refused) {
            _ = try await database.offMain { _ throws(Refused) -> Int in throw Refused() }
            Issue.record("the work didn't throw")
        } catch {
            #expect(error == Refused())
        }
        // Work that can't throw needs no `try`.
        #expect(await database.offMain { _ in 42 } == 42)
    }

    @Test func eitherHoldFollowsTheSameMail() async throws {
        let database = try await OffMainDatabase.open(url: Self.url())
        let (account, thread) = (account, thread)
        _ = try await database.offMain { try $0.save(account) }
        var held = database.threads(in: .inbox).makeAsyncIterator()
        var blocking = database.blocking.threads(in: .inbox).makeAsyncIterator()
        #expect(try await held.next(isolation: #isolation)?.isEmpty == true)
        #expect(try await blocking.next(isolation: #isolation)?.isEmpty == true)

        try await database.offMain { try $0.upsert([thread]) }
        #expect(try await held.next(isolation: #isolation)?.map(\.id) == [thread.id])
        #expect(try await blocking.next(isolation: #isolation)?.map(\.id) == [thread.id])
    }

    // Exit tests run in a child process, which only macOS and Linux can start; the iOS build of the tests leaves it out.
    #if os(macOS) || os(Linux)
        @Test func theSameReadOffTheMainActorDoesNot() async {
            await #expect(processExitsWith: .success) {
                let database = try await OffMainDatabase.open(url: OffMainDatabaseTests.url())
                _ = try? database.blocking.accounts()
            }
        }

        // The trap is armed only in Debug builds.
        #if DEBUG
            /// How a failed `dispatchPrecondition` ends the process: a trap instruction, whose signal is the CPU's.
            private static var trapped: ExitTest.Condition {
                #if arch(x86_64)
                    .signal(SIGILL)
                #else
                    .signal(SIGTRAP)
                #endif
            }

            @Test func aReadOnTheMainActorTrapsInDebug() async {
                await #expect(processExitsWith: Self.trapped) {
                    let database = try await OffMainDatabase.open(url: OffMainDatabaseTests.url())
                    await MainActor.run { _ = try? database.blocking.accounts() }
                }
            }

            @Test func openingOnTheMainActorTrapsInDebug() async {
                await #expect(processExitsWith: Self.trapped) {
                    await MainActor.run { _ = try? MailDatabase(url: OffMainDatabaseTests.url()) }
                }
            }
        #endif
    #endif
}
