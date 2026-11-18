import Foundation
import MailCore
import Synchronization
import Testing

/// Parts kept on disk, so an inline image or an opened attachment downloads once and shows offline after.
struct AttachmentFilesTests {
    private let files = AttachmentFiles(
        root: FileManager.default.temporaryDirectory.appending(path: "AttachmentFilesTests-\(UUID().uuidString)"))
    private let message = Message.ID(accountID: AccountID(rawValue: "a1"), messageID: "m1")
    private let image = Attachment(
        id: "2", filename: "logo.png", mimeType: "image/png", size: 4, contentID: "logo@x", isInline: true)

    @Test func aPartIsKeptWhereTheCacheCapLooksForIt() async throws {
        #expect(await files.cachedData(for: image, in: message) == nil)
        let url = try await files.keep(Data("logo".utf8), for: image, in: message)
        #expect(url == files.root.appending(path: "a1/m1-2/logo.png"))
        #expect(await files.cachedData(for: image, in: message) == Data("logo".utf8))
        #expect(await files.cachedFile(for: image, in: message) == url)
    }

    @Test func usingAPartStampsItsFile() async throws {
        let url = try await files.keep(Data("logo".utf8), for: image, in: message)
        let later = Date(timeIntervalSinceNow: 3600).rounded
        _ = await files.cachedData(for: image, in: message, at: later)
        let stamped = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(stamped?.rounded == later)
    }

    @Test(arguments: [("../../etc/passwd", "-..-etc-passwd"), (".hidden", "hidden"), ("  ", "Attachment")])
    func filenamesStayInTheirFolder(name: String, kept: String) {
        #expect(AttachmentFiles.safeFilename(name) == kept)
    }
}

extension Date {
    /// To the second, as file dates keep it.
    fileprivate var rounded: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded()) }
}

/// A message's source kept for a moment, so the parts read from it one after another download it once.
struct RecentSourcesTests {
    /// Counts fetches.
    final class Server: Sendable {
        private let count = Mutex(0)
        var fetches: Int { count.withLock { $0 } }
        func fetch(_ data: Data?) -> @Sendable () async throws -> Data? {
            { [self] in
                count.withLock { $0 += 1 }
                return data
            }
        }
    }

    @Test func aSourceReadAMomentAgoIsReused() async throws {
        let sources = RecentSources()
        let server = Server()
        let first = try await sources.source(of: "m1", fetch: server.fetch(Data("raw".utf8)))
        let second = try await sources.source(of: "m1", fetch: server.fetch(Data("other".utf8)))
        #expect(first == Data("raw".utf8))
        #expect(second == first)
        #expect(server.fetches == 1)
    }

    @Test func readsAtOnceShareOneFetch() async throws {
        let sources = RecentSources()
        let server = Server()
        let results = try await withThrowingTaskGroup(of: Data?.self) { group in
            for _ in 0..<5 {
                group.addTask { try await sources.source(of: "m1", fetch: server.fetch(Data("raw".utf8))) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.allSatisfy { $0 == Data("raw".utf8) })
        #expect(server.fetches == 1)
    }

    @Test func aSourceIsFetchedAgainOnceItsMomentPasses() async throws {
        let sources = RecentSources(lifetime: .zero)
        let server = Server()
        _ = try await sources.source(of: "m1", fetch: server.fetch(Data("raw".utf8)))
        _ = try await sources.source(of: "m1", fetch: server.fetch(Data("raw".utf8)))
        #expect(server.fetches == 2)
    }

    @Test func aSourceOverTheLimitIsNotKept() async throws {
        let sources = RecentSources(byteLimit: 2)
        let server = Server()
        _ = try await sources.source(of: "m1", fetch: server.fetch(Data("raw".utf8)))
        _ = try await sources.source(of: "m1", fetch: server.fetch(Data("raw".utf8)))
        #expect(server.fetches == 2)
    }

    @Test func aFailedFetchIsTriedAgain() async throws {
        let sources = RecentSources()
        let server = Server()
        await #expect(throws: URLError.self) {
            try await sources.source(of: "m1") { throw URLError(.notConnectedToInternet) }
        }
        #expect(try await sources.source(of: "m1", fetch: server.fetch(Data("raw".utf8))) == Data("raw".utf8))
    }
}
