public import Foundation
public import MailCore
public import Observation

/// One transfer from this device: its code, and the wait for a device that scanned it.
public protocol TransferHosting {
    /// What the QR code shows.
    var code: URL { get }
    /// Waits for a device that scanned the code and sends it the accounts `approve` picks, given that device's name;
    /// `approve` answers `nil` to turn it down. Returns how many accounts went. Throws `TransferServer.Failure.expired`
    /// once the code is too old.
    func serve(approve: @escaping @MainActor @Sendable (String) async -> Set<AccountID>?) async throws -> Int
}

/// Sending accounts to another device by QR code: unlock, show the code, then ask which accounts go to the device
/// that scanned it.
@Observable
public final class TransferSending {
    public enum Stage {
        /// Waiting for Face ID or the passcode, since the code hands over sign-ins.
        case unlocking
        /// The device owner didn't unlock.
        case locked
        /// Showing the code until a device scans it.
        case showing(URL)
        /// A device scanned the code: the reader picks the accounts it gets, or turns it down.
        case choosing(device: String, answer: CheckedContinuation<Set<AccountID>?, Never>)
        case sending
        case sent(count: Int)
        case declined
        case expired
        case failed(any Error)
    }

    public private(set) var stage = Stage.unlocking
    public let accounts: [Account]
    /// The accounts that go to the device, while choosing. All start chosen.
    public var chosen: Set<AccountID>
    @ObservationIgnored private let unlock: () async -> Bool
    @ObservationIgnored private let host: () -> any TransferHosting

    /// `unlock` asks for Face ID or the passcode; `host` makes the transfer, with its code, once unlocked.
    public init(accounts: [Account], unlock: @escaping () async -> Bool, host: @escaping () -> any TransferHosting) {
        self.accounts = accounts
        chosen = Set(accounts.map(\.id))
        self.unlock = unlock
        self.host = host
    }

    /// Why Face ID or the passcode is asked for, as the system prompt shows it.
    public static var unlockReason: String {
        String(
            localized: "Show the code that moves your accounts to another device.", table: "Transfer", bundle: .module,
            comment: "Why Face ID or the passcode is asked for before showing a transfer code")
    }

    /// Runs the transfer until it ends or the task that runs it is cancelled, as when the screen closes.
    public func run() async {
        stage = .unlocking
        guard await unlock() else {
            stage = .locked
            return
        }
        let host = host()
        stage = .showing(host.code)
        do {
            let sent = try await host.serve { [weak self] device in await self?.ask(device) }
            stage = sent > 0 ? .sent(count: sent) : .declined
        } catch TransferServer.Failure.expired {
            stage = .expired
        } catch is CancellationError {
            // The screen closed.
        } catch {
            stage = .failed(error)
        }
    }

    /// Sends the chosen accounts to the device that asked.
    public func send() {
        guard case .choosing(_, let answer) = stage else { return }
        stage = .sending
        answer.resume(returning: chosen)
    }

    /// Sends the device nothing.
    public func decline() {
        guard case .choosing(_, let answer) = stage else { return }
        stage = .sending
        answer.resume(returning: nil)
    }

    private func ask(_ device: String) async -> Set<AccountID>? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { stage = .choosing(device: device, answer: $0) }
        } onCancel: {
            // Answers on the main actor, where the stage lives, so `serve` hears no and ends with the screen. Nothing
            // waits on this task: it only resumes the continuation, once, if the question is still open.
            Task { @MainActor [weak self] in self?.decline() }
        }
    }
}
