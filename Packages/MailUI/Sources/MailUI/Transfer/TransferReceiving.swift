public import Foundation
public import MailCore
public import Observation

/// Receiving accounts from another device: scan its code, wait for the reader to approve there, then add them.
@Observable
public final class TransferReceiving {
    public enum Stage {
        /// Looking for a code.
        case scanning
        /// Finding the device that showed `code` on the local network.
        case connecting(URL)
        /// Asked; the reader approves on the other device.
        case waiting
        case added([Account])
        case declined
        case failed(any Error)
    }

    /// How a transfer that reached the other device is going, as `receive` reports it.
    public enum Progress: Sendable {
        case connected
    }

    /// One transfer under way: the task receiving from a code, known by its own ID so that what a stopped one
    /// reports late never moves the next one on.
    private struct Run {
        let id: UUID
        let task: Task<Void, Never>
    }

    /// Where receiving stands, with the run under way while there is one. Only `use`, `stop`, `scanAgain` and a
    /// run's own end change it.
    private enum Phase {
        case scanning
        case connecting(URL, Run)
        case waiting(Run)
        case ended(Ending)
    }

    /// How a transfer that ran its course ended.
    private enum Ending {
        case added([Account])
        case declined
        case failed(any Error)
    }

    /// What a run's receive came back with.
    private enum Outcome {
        case added([Account])
        case declined
        /// Cancelled, as `stop()` does, or a failure the cancellation caused.
        case cancelled
        case failed(any Error)
    }

    private var phase = Phase.scanning
    @ObservationIgnored private let receive:
        (_ code: URL, _ progress: @escaping @MainActor (Progress) -> Void) async throws -> [Account]

    /// `receive` connects to the device whose code was scanned, waits for its answer, and adds the accounts. `code`
    /// is one the Camera app already scanned, which receiving starts from at once.
    public init(
        code: URL? = nil,
        receive: @escaping (_ code: URL, _ progress: @escaping @MainActor (Progress) -> Void) async throws -> [Account]
    ) {
        self.receive = receive
        if let code { use(code) }
    }

    /// A run's task holds the model only weakly, so a screen that goes away without `stop()` still ends the transfer
    /// here.
    isolated deinit {
        receiving?.cancel()
    }

    public var stage: Stage {
        switch phase {
        case .scanning: .scanning
        case .connecting(let code, _): .connecting(code)
        case .waiting: .waiting
        case .ended(.added(let accounts)): .added(accounts)
        case .ended(.declined): .declined
        case .ended(.failed(let error)): .failed(error)
        }
    }

    /// The task receiving from the code, while one is under way.
    var receiving: Task<Void, Never>? {
        current?.task
    }

    private var current: Run? {
        switch phase {
        case .connecting(_, let run), .waiting(let run): run
        case .scanning, .ended: nil
        }
    }

    /// Whether `code` is a transfer code, so the scanner only stops for one.
    public static func isCode(_ text: String) -> Bool {
        URL(string: text).flatMap(TransferInvitation.init(url:)) != nil
    }

    /// Receives from a code scanned here or by the Camera app, also in place of a transfer that failed or was turned
    /// down, even from the same code. A code that comes while one is under way, or after accounts were added, is
    /// ignored.
    public func use(_ code: URL) {
        switch phase {
        case .scanning, .ended(.declined), .ended(.failed): break
        case .connecting, .waiting, .ended(.added): return
        }
        let id = UUID()
        let receive = receive
        // The task doesn't hold the model while it waits on the network, so the model's deinit can cancel it.
        let task = Task { [weak self] in
            let outcome = await Self.outcome(of: receive, from: code) { [weak self] progress in
                switch progress {
                case .connected: self?.connected(id)
                }
            }
            self?.end(id, with: outcome)
        }
        phase = .connecting(code, Run(id: id, task: task))
    }

    /// Back to the scanner, after a failure or a decline.
    public func scanAgain() {
        switch phase {
        case .ended(.declined), .ended(.failed): phase = .scanning
        case .scanning, .connecting, .waiting, .ended(.added): return
        }
    }

    /// Stops receiving, as when the screen closes, and goes back to the scanner at once. The other device hears
    /// nothing more. If the accounts were added all the same, the run still says so when it ends (`end`).
    public func stop() {
        guard let receiving else { return }
        receiving.cancel()
        phase = .scanning
    }

    private static func outcome(
        of receive: (_ code: URL, _ progress: @escaping @MainActor (Progress) -> Void) async throws -> [Account],
        from code: URL, progress: @escaping @MainActor (Progress) -> Void
    ) async -> Outcome {
        do {
            return .added(try await receive(code, progress))
        } catch TransferReceiver.Failure.declined {
            return .declined
        } catch {
            // A transfer stopped under way fails in its own words, as a URL error does, but is no failure.
            return error is CancellationError || Task.isCancelled ? .cancelled : .failed(error)
        }
    }

    /// Run `id` reached the other device, while it is still the one connecting.
    private func connected(_ id: UUID) {
        guard case .connecting(_, let run) = phase, run.id == id else { return }
        phase = .waiting(run)
    }

    /// Run `id` ended. Its result counts while it is the run under way. Accounts it added count after a `stop()`
    /// too, as the scanner it went back to has nothing yet: they are on this device now.
    private func end(_ id: UUID, with outcome: Outcome) {
        let isCurrent = current?.id == id
        switch outcome {
        case .added(let accounts):
            let isStopped = if case .scanning = phase { true } else { false }
            guard isCurrent || isStopped else { return }
            phase = .ended(.added(accounts))
        case .declined:
            guard isCurrent else { return }
            phase = .ended(.declined)
        case .failed(let error):
            guard isCurrent else { return }
            phase = .ended(.failed(error))
        case .cancelled:
            guard isCurrent else { return }
            phase = .scanning
        }
    }
}
