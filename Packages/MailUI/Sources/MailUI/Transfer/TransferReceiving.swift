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

    public private(set) var stage = Stage.scanning
    /// Receiving from the code in `.connecting`, until it ends or the screen closes (`stop()`).
    @ObservationIgnored private(set) var receiving: Task<Void, Never>?
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

    isolated deinit {
        receiving?.cancel()
    }

    /// Whether `code` is a transfer code, so the scanner only stops for one.
    public static func isCode(_ text: String) -> Bool {
        URL(string: text).flatMap(TransferInvitation.init(url:)) != nil
    }

    /// Receives from a code scanned here or by the Camera app, also in place of a transfer that failed or was turned
    /// down, even from the same code. A code that comes while one is under way, or after accounts were added, is
    /// ignored.
    public func use(_ code: URL) {
        switch stage {
        case .scanning, .declined, .failed: break
        case .connecting, .waiting, .added: return
        }
        stage = .connecting(code)
        receiving = Task { [weak self] in await self?.receive(from: code) }
    }

    /// Back to the scanner, after a failure or a decline.
    public func scanAgain() {
        stage = .scanning
    }

    /// Stops receiving, as when the screen closes. The other device hears nothing more.
    public func stop() {
        receiving?.cancel()
        receiving = nil
    }

    private func receive(from code: URL) async {
        do {
            let accounts = try await receive(code) { [weak self] progress in
                switch progress {
                case .connected: self?.stage = .waiting
                }
            }
            stage = .added(accounts)
        } catch TransferReceiver.Failure.declined {
            stage = .declined
        } catch is CancellationError {
            stage = .scanning
        } catch {
            stage = .failed(error)
        }
    }
}
