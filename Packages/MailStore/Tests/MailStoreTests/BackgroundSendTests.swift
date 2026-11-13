import Foundation
import MailCore
import Testing

@testable import MailStore

/// A send is handed to an upload that outlives the app, and leaves the queue only when that upload's outcome is
/// in. However launches come and go around it, the message goes once.
struct BackgroundSendTests {
    private let bench: SendBench
    private var database: MailDatabase { bench.database }
    private var server: FakeMailServer { bench.server }
    private var uploads: FakeUploads { bench.uploads }
    private var account: AccountID { bench.account }

    init() throws {
        bench = try SendBench()
    }

    private func uploading() throws -> [OutgoingMessage] {
        try database.uploadingMessages(for: account)
    }

    @Test func aDueMessageIsHandedOverFromAFileAndLeavesTheQueueWhenItsUploadIsAnswered() async throws {
        try await bench.commands().send(bench.draft(), after: .zero)
        let sender = bench.sender()
        #expect(await sender.flush().isEmpty, "handed over, not gone yet")
        let upload = try #require(uploads.started.first)
        #expect(upload.request.value(forHTTPHeaderField: "Thread") == "t1")
        #expect(String(decoding: try Data(contentsOf: upload.file), as: UTF8.self).contains("Subject: Hello"))
        #expect(try uploading().count == 1)
        #expect(try await bench.commands().cancelSend(bench.draft().id) == nil, "too late to undo")

        let (id, outcome) = try #require(try uploads.finishAll().first)
        #expect(await sender.complete(id, with: outcome)?.subject == "Hello")
        #expect(server.sent.count == 1)
        #expect(try uploading().isEmpty)
        #expect(bench.uploadFiles().isEmpty, "the upload's file goes with it")
    }

    @Test func undoWithinTheWindowMeansNothingIsUploaded() async throws {
        let draft = bench.draft()
        try await bench.commands().send(draft, after: .seconds(10))
        await bench.sender().flush()
        #expect(try await bench.commands().cancelSend(draft.id) == draft)
        for _ in 0..<60 { _ = bench.clock.next() }  // the window closes
        try await bench.deliver()
        #expect(uploads.started.isEmpty)
        #expect(server.sent.isEmpty)
    }

    @Test func aRelaunchWhileTheUploadIsUnderWayDoesNotUploadItAgain() async throws {
        try await bench.commands().send(bench.draft(), after: .zero)
        await bench.sender().flush()
        let relaunched = bench.sender()
        await relaunched.flush()
        #expect(uploads.started.count == 1)
        #expect(try await bench.deliver(with: relaunched).count == 1, "the new launch hears the outcome")
        #expect(server.sent.count == 1)
    }

    @Test func anOutcomeHeardTwiceCountsOnce() async throws {
        try await bench.commands().send(bench.draft(), after: .zero)
        let sender = bench.sender()
        await sender.flush()
        let (id, outcome) = try #require(try uploads.finishAll().first)
        #expect(await sender.complete(id, with: outcome) != nil)
        #expect(await bench.sender().complete(id, with: outcome) == nil)
        #expect(await sender.flush().isEmpty)
        #expect(server.sent.count == 1)
    }

    @Test func aLostUploadThatWentIsFoundInSentMail() async throws {
        server.answerSends(with: nil)
        try await bench.commands().send(bench.draft(), after: .zero)
        let sender = bench.sender()
        await sender.flush()
        let (id, outcome) = try #require(try uploads.finishAll().first)
        #expect(outcome == .noResponse)
        #expect(await sender.complete(id, with: outcome)?.subject == "Hello")
        #expect(try uploading().isEmpty)
        #expect(server.sent.count == 1)
    }

    @Test func anUploadThatNeverReportedIsSettledOnTheNextLaunchWithoutSendingTwice() async throws {
        try await bench.commands().send(bench.draft(), after: .zero)
        await bench.sender().flush()
        uploads.loseAll()
        // Can't ask yet: it stays uploading, and nothing is sent again.
        server.failLookup(with: URLError(.notConnectedToInternet))
        try await bench.deliver()
        #expect(try uploading().count == 1)
        server.failLookup(with: nil)
        #expect(try await bench.deliver().isEmpty)
        #expect(uploads.started.count == 1, "never uploaded twice")
        #expect(try await bench.failures() == [.unconfirmed], "for the writer to send again, knowing")
        #expect(bench.uploadFiles().isEmpty)
    }

    @Test func rateLimitedSendsAreUploadedAgain() async throws {
        server.answerSends(with: 429)
        try await bench.commands().send(bench.draft(), after: .zero)
        #expect(try await bench.deliver().isEmpty)
        #expect(try database.dueMessages(for: account, by: .distantFuture).count == 1, "queued for another try")
        server.answerSends(with: 200)
        #expect(try await bench.deliver().count == 1)
        #expect(uploads.started.count == 2)
        #expect(server.sent.count == 1)
    }

    @Test func aMessageRefusedForGoodIsUploadedOnceAndKeptForTheWriter() async throws {
        server.answerSends(with: 413)
        try await bench.commands().send(bench.draft(), after: .zero)
        try await bench.deliver()
        try await bench.deliver()
        #expect(uploads.started.count == 1, "not uploaded again on the next flush")
        #expect(try await bench.failures() == [.rejected])
    }

    @Test func aServerErrorIsCheckedAgainstSentMailRatherThanSentAgain() async throws {
        server.answerSends(with: 503)
        try await bench.commands().send(bench.draft(), after: .zero)
        #expect(try await bench.deliver().isEmpty)
        #expect(try database.dueMessages(for: account, by: .distantFuture).isEmpty, "not retried by itself")
        #expect(uploads.started.count == 1)
        #expect(try await bench.failures() == [.unconfirmed])
    }

    @Test func aReplyWhoseThreadIsGoneGoesOnItsOwn() async throws {
        server.answerSends(with: 404)
        try await bench.commands().send(bench.draft(), after: .zero)
        try await bench.deliver()
        server.answerSends(with: 200)
        try await bench.deliver()
        #expect(uploads.started.last?.request.value(forHTTPHeaderField: "Thread") == nil)
        #expect(server.sent.count == 1)
    }

    @Test func aTransportThatWontTakeTheUploadLeavesTheMessageQueued() async throws {
        uploads.failUpload(with: URLError(.cannotCreateFile))
        try await bench.commands().send(bench.draft(), after: .zero)
        try await bench.deliver()
        #expect(try database.dueMessages(for: account, by: .distantFuture).count == 1)
        #expect(bench.uploadFiles().isEmpty)
        uploads.failUpload(with: nil)
        #expect(try await bench.deliver().count == 1)
    }

    @Test func filesNoUploadNeedsAreClearedOnFlush() async throws {
        let folder = bench.uploadsDirectory.appending(path: account.rawValue)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("left by a killed launch".utf8).write(to: folder.appending(path: "\(UUID().uuidString).upload"))
        try await bench.commands().send(bench.draft(), after: .zero)
        await bench.sender().flush()
        #expect(bench.uploadFiles().count == 1, "only the upload under way keeps its file")
    }

    @Test func theDeliveryStateSurvivesTheDatabase() throws {
        let id = UploadID()
        for delivery: OutgoingMessage.Delivery in [.queued, .uploading(id), .failed(.unconfirmed)] {
            let message = OutgoingMessage(draft: bench.draft(), sendAt: .now, delivery: delivery)
            try database.enqueue(message)
            #expect(try database.update(message.id, from: delivery, to: message), "\(delivery)")
            #expect(try database.update(message.id, from: .failed(.rejected), to: nil) == false)
            #expect(try database.update(message.id, from: delivery, to: nil), "taken off by its own state")
        }
        #expect(try uploading().isEmpty)
    }

    @Test func aProviderThatSendsOverItsOwnConnectionSendsWithoutAnUpload() async throws {
        let bench = try SendBench(sendPath: .direct)
        try await bench.commands().send(bench.draft(), after: .zero)

        #expect(await bench.sender().flush().map(\.subject) == ["Hello"])
        #expect(bench.uploads.started.isEmpty)
        #expect(bench.server.sent.count == 1)
        #expect(try bench.database.dueMessages(for: bench.account, by: .distantFuture).isEmpty)
    }

    @Test func aDirectSendThatIsRefusedIsKeptForTheWriter() async throws {
        let bench = try SendBench(sendPath: .direct)
        bench.server.answerSends(with: 400)
        try await bench.commands().send(bench.draft(), after: .zero)

        #expect(await bench.sender().flush().isEmpty)
        #expect(try await bench.failures() == [.rejected])
    }
}
