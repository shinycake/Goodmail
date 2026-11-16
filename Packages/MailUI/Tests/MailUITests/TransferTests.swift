import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransferSendingTests {
    private let phone = Account(id: AccountID(rawValue: "p"), email: "me@gmail.com", color: .blue, service: .gmail)
    private let work = Account(id: AccountID(rawValue: "w"), email: "me@outlook.com", color: .orange, service: .outlook)
    private let code = URL(string: "goodmail-transfer://1?s=x")!

    @Test func theReaderPicksWhatTheDeviceThatScannedGets() async throws {
        let host = FakeHost(code: code, outcome: .asks("iPad"))
        let model = TransferSending(accounts: [phone, work], unlock: { true }, host: { host })
        let running = Task { await model.run() }

        try await model.waitUntil { if case .choosing(let device, _) = $0 { device == "iPad" } else { false } }
        #expect(model.chosen == [phone.id, work.id], "every account starts chosen")
        model.chosen.remove(work.id)
        model.send()
        await running.value

        #expect(host.answer == [phone.id])
        #expect(model.isStage { if case .sent(1) = $0 { true } else { false } })
    }

    @Test func turningTheDeviceDownSendsNothing() async throws {
        let host = FakeHost(code: code, outcome: .asks("iPad"))
        let model = TransferSending(accounts: [phone], unlock: { true }, host: { host })
        let running = Task { await model.run() }

        try await model.waitUntil { if case .choosing = $0 { true } else { false } }
        model.decline()
        await running.value

        #expect(host.answer == nil)
        #expect(model.isStage { if case .declined = $0 { true } else { false } })
    }

    @Test func closingTheScreenWhileChoosingTurnsTheDeviceDown() async throws {
        let host = FakeHost(code: code, outcome: .asks("iPad"))
        let model = TransferSending(accounts: [phone], unlock: { true }, host: { host })
        let running = Task { await model.run() }

        try await model.waitUntil { if case .choosing = $0 { true } else { false } }
        running.cancel()
        await running.value

        #expect(host.asked)
        #expect(host.answer == nil)
    }

    @Test func noCodeShowsWithoutUnlocking() async {
        var made = false
        let model = TransferSending(
            accounts: [phone], unlock: { false },
            host: {
                made = true
                return FakeHost(code: code, outcome: .expires)
            })

        await model.run()

        #expect(!made, "the code holds the way in, so it isn't even made")
        #expect(model.isStage { if case .locked = $0 { true } else { false } })
    }

    @Test func aCodeNobodyUsedExpires() async {
        let model = TransferSending(
            accounts: [phone], unlock: { true }, host: { FakeHost(code: code, outcome: .expires) })

        await model.run()

        #expect(model.isStage { if case .expired = $0 { true } else { false } })
    }

    @Test func aBrokenConnectionFails() async {
        let model = TransferSending(
            accounts: [phone], unlock: { true }, host: { FakeHost(code: code, outcome: .fails) })

        await model.run()

        #expect(model.isStage { if case .failed = $0 { true } else { false } })
    }
}

@MainActor
struct TransferReceivingTests {
    private let home = Account(id: AccountID(rawValue: "h"), email: "me@icloud.com", color: .green, service: .icloud)
    private let code = URL(string: "goodmail-transfer://1?s=x")!

    @Test func scanningReceivesAndAddsTheAccounts() async {
        let model = TransferReceiving { _, progress in
            progress(.connected)
            return [home]
        }

        model.use(code)
        await model.receiving?.value

        guard case .added(let accounts) = model.stage else {
            Issue.record("not added: \(model.stage)")
            return
        }
        #expect(accounts == [home])
    }

    @Test func aCodeFromTheCameraStartsAtOnce() async {
        var codes: [URL] = []
        let model = TransferReceiving(code: code) { code, _ in
            codes.append(code)
            return [home]
        }

        guard case .connecting(code) = model.stage else {
            Issue.record("not connecting: \(model.stage)")
            return
        }
        await model.receiving?.value
        #expect(codes == [code])
    }

    @Test func aDeclineSaysSoAndScanningAgainStartsOver() async {
        let model = TransferReceiving(code: code) { _, _ in throw TransferReceiver.Failure.declined }

        await model.receiving?.value
        guard case .declined = model.stage else {
            Issue.record("not declined: \(model.stage)")
            return
        }

        model.scanAgain()
        guard case .scanning = model.stage else {
            Issue.record("not scanning: \(model.stage)")
            return
        }
    }

    @Test func theSameCodeAgainAfterAFailureIsReceivedFromAgain() async {
        var attempts = 0
        let model = TransferReceiving(code: code) { _, _ in
            attempts += 1
            throw URLError(.timedOut)
        }
        await model.receiving?.value

        model.use(code)
        await model.receiving?.value

        #expect(attempts == 2, "the Camera opening the same code again tries again")
    }

    @Test func aCodeFromTheCameraAfterADeclineIsReceivedFrom() async {
        let next = URL(string: "goodmail-transfer://1?s=y")!
        var codes: [URL] = []
        let model = TransferReceiving(code: code) { code, _ in
            codes.append(code)
            throw TransferReceiver.Failure.declined
        }
        await model.receiving?.value

        model.use(next)
        await model.receiving?.value

        #expect(codes == [code, next])
    }

    @Test func aCodeAfterAccountsWereAddedIsIgnored() async {
        var received = 0
        let model = TransferReceiving { _, _ in
            received += 1
            return []
        }
        model.use(code)
        await model.receiving?.value
        model.use(code)
        await model.receiving?.value

        #expect(received == 1, "the first transfer ended in added, not scanning")
    }

    @Test func closingTheScreenStopsReceivingAndGoesBackToScanning() async {
        let model = TransferReceiving(code: code) { _, _ in
            try await Task.sleep(for: .seconds(3600))
            return []
        }
        let receiving = model.receiving

        model.stop()
        await receiving?.value

        guard case .scanning = model.stage else {
            Issue.record("still receiving: \(model.stage)")
            return
        }
    }

    @Test(arguments: [
        (
            "goodmail-transfer://1?s=Goodmail-abc&k=BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc&c=CQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQk",
            true
        ),
        ("https://example.com", false),
        ("not a code", false),
    ])
    func onlyATransferCodeStopsTheScanner(_ text: String, isCode: Bool) {
        #expect(TransferReceiving.isCode(text) == isCode)
    }
}

/// A transfer whose network side is scripted: a device that asks, a code that expires, or a connection that breaks.
@MainActor
private final class FakeHost: TransferHosting {
    enum Outcome {
        case asks(String)
        case expires
        case fails
    }

    let code: URL
    private let outcome: Outcome
    private(set) var asked = false
    private(set) var answer: Set<AccountID>?

    init(code: URL, outcome: Outcome) {
        self.code = code
        self.outcome = outcome
    }

    func serve(approve: @escaping @MainActor @Sendable (String) async -> Set<AccountID>?) async throws -> Int {
        switch outcome {
        case .asks(let device):
            asked = true
            answer = await approve(device)
            return answer?.count ?? 0
        case .expires: throw TransferServer.Failure.expired
        case .fails: throw URLError(.networkConnectionLost)
        }
    }
}

extension TransferSending {
    fileprivate func isStage(_ matches: (Stage) -> Bool) -> Bool { matches(stage) }

    /// Lets the transfer run until its stage matches, as the screen would wait for it.
    fileprivate func waitUntil(_ matches: (Stage) -> Bool) async throws {
        while !matches(stage) {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}
