import Foundation
import MailCore
import Testing

@testable import MailStore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A message shared from another app goes at once from the Share extension, and whatever doesn't finish there waits
/// in the shared queue in the state the app's sender finishes it from, without ever going twice.
struct ImmediateDeliveryTests {
    private let scratch = FileManager.default.temporaryDirectory.appending(path: "Immediate-\(UUID().uuidString)")

    private func deliver(
        _ draft: Draft, as purpose: OutgoingMessage.Purpose = .send, on bench: SendBench
    ) async throws -> ImmediateDelivery.Outcome {
        try await delivery(draft, as: purpose, on: bench).run()
    }

    private func delivery(
        _ draft: Draft, as purpose: OutgoingMessage.Purpose = .send, on bench: SendBench
    ) -> ImmediateDelivery {
        ImmediateDelivery(
            draft, as: purpose, provider: bench.server, store: bench.database, http: ServerHTTP(server: bench.server),
            scratch: scratch, now: bench.clock.next)
    }

    private func queue(of bench: SendBench) throws -> [OutgoingMessage] {
        try bench.database.dueMessages(for: bench.account, by: .distantFuture)
            + bench.database.uploadingMessages(for: bench.account)
    }

    @Test func anUploadGoesAtOnceAndLeavesNothingQueued() async throws {
        let bench = try SendBench()

        #expect(try await deliver(bench.draft(), on: bench) == .done)
        #expect(bench.server.sent.count == 1)
        #expect(try queue(of: bench).isEmpty)
    }

    @Test func aDirectSendGoesAndFilesItsCopy() async throws {
        let bench = try SendBench(sendPath: .direct)

        #expect(try await deliver(bench.draft(), on: bench) == .done)
        #expect(bench.server.sent.count == 1)
        #expect(bench.server.filedSent.count == 1)
        #expect(try queue(of: bench).isEmpty)
    }

    @Test(arguments: [FakeMailServer.SendPath.upload, .direct])
    func offlineTheMessageWaitsInTheSharedQueueAndTheAppSendsItOnce(path: FakeMailServer.SendPath) async throws {
        let bench = try SendBench(sendPath: path)
        bench.server.failPrepare(with: URLError(.notConnectedToInternet))

        #expect(try await deliver(bench.draft("Later"), on: bench) == .handedOver(.queued))
        #expect(bench.server.sent.isEmpty)

        bench.server.failPrepare(with: nil)
        #expect(try await bench.deliver().map(\.subject) == ["Later"])
        #expect(bench.server.sent.count == 1)
    }

    @Test(arguments: [nil, 503])
    func anAnswerThatDoesntSayIsLeftForTheAppToAskAboutLaterNotToSendAgain(status: Int?) async throws {
        let bench = try SendBench()
        // A message that went (no answer), or a server error that may have sent it: either way, asking at once could
        // miss a message the service's search hasn't caught up with.
        bench.server.answerSends(with: status)

        let outcome = try await deliver(bench.draft(), on: bench)
        guard case .handedOver(.uploading) = outcome else {
            Issue.record("Expected an upload left to settle, got \(outcome)")
            return
        }

        bench.server.answerSends(with: 200)
        let confirmed = try await bench.deliver()
        #expect(confirmed.count == (status == nil ? 1 : 0), "only a message that went is confirmed")
        #expect(bench.server.sent.count == (status == nil ? 1 : 0), "never sent a second time")
        #expect(try await bench.failures() == (status == nil ? [] : [.unconfirmed]))
    }

    @Test(arguments: [401, 404])
    func aTurnedAwayOrThreadlessSendWaitsForTheAppAndGoesOnce(status: Int) async throws {
        let bench = try SendBench()
        bench.server.answerSends(with: status)

        #expect(try await deliver(bench.draft(), on: bench) == .handedOver(.queued))

        bench.server.answerSends(with: 200)
        #expect(try await bench.deliver().count == 1)
        #expect(bench.server.sent.count == 1)
    }

    @Test func aDirectSendTheServerRefusesIsLeftFailed() async throws {
        let bench = try SendBench(sendPath: .direct)
        bench.server.answerSends(with: 400)

        #expect(try await deliver(bench.draft(), on: bench) == .handedOver(.failed(.rejected)))
        #expect(bench.server.sent.isEmpty)
    }

    @Test func handingOverBeforeTheAttemptKeepsTheMessageOnceForTheApp() async throws {
        let bench = try SendBench()
        let delivery = delivery(bench.draft("Interrupted"), on: bench)

        #expect(try delivery.handOver() == .handedOver(.queued), "as when iOS is about to suspend the extension")
        #expect(try await delivery.run() == .handedOver(.queued), "nothing more is attempted")
        #expect(bench.server.sent.isEmpty)
        #expect(try queue(of: bench).map(\.draft.subject) == ["Interrupted"])
        #expect(try await bench.deliver().count == 1)
    }

    @Test func aRefusedMessageIsLeftFailedForTheWriter() async throws {
        let bench = try SendBench()
        bench.server.answerSends(with: 400)

        #expect(try await deliver(bench.draft(), on: bench) == .handedOver(.failed(.rejected)))
        #expect(try await bench.failures() == [.rejected])
    }

    @Test func aDraftIsSavedAtOnceAndTheAppKnowsItsCopy() async throws {
        let bench = try SendBench()
        let draft = bench.draft()

        #expect(try await deliver(draft, as: .saveDraft, on: bench) == .done)
        #expect(bench.server.drafts.count == 1)
        #expect(try bench.database.savedCopy(of: draft.id) != nil)
        #expect(try queue(of: bench).isEmpty)
    }

    @Test func theAppsOwnQueueIsLeftAlone() async throws {
        let bench = try SendBench()
        try await bench.commands().send(bench.draft("In its undo window"), after: .seconds(30))
        try await bench.commands().send(bench.draft("Due"), after: .zero)

        #expect(try await deliver(bench.draft("Shared"), on: bench) == .done)
        #expect(bench.server.sent.count == 1)
        #expect(try queue(of: bench).map(\.draft.subject).sorted() == ["Due", "In its undo window"])
    }
}

/// The service as the network reaches it: an upload that `FakeMailServer` takes in, or a dropped connection when it
/// loses the answer.
private struct ServerHTTP: HTTPClient {
    let server: FakeMailServer

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch server.receive(request, body: request.httpBody ?? Data()) {
        case .response(let status, let body):
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case .noResponse:
            throw URLError(.networkConnectionLost)
        }
    }
}
