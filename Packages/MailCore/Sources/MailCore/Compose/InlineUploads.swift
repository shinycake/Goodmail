public import Foundation
import Synchronization

#if canImport(FoundationNetworking)
    public import FoundationNetworking  // URLSession on Linux
#endif

/// Uploads a send while its process waits for it, for one that can't hear a background session's outcome later: the
/// watch app, which has no background upload session yet, and the Share extension, which is gone once its sheet
/// closes. `upload` returns only once the service answered or the transfer failed. The outcome is kept for whoever
/// flushed the sender to hand back to it (`takeOutcomes`), so nothing finishes on its own behind anyone's back.
public final class InlineUploads: UploadTransport {
    private struct State {
        var running: Set<UploadID> = []
        var finished: [(UploadTicket, UploadOutcome)] = []
    }

    private let http: any HTTPClient
    private let state = Mutex(State())

    public init(http: any HTTPClient = URLSession.shared) {
        self.http = http
    }

    public func upload(_ request: URLRequest, from file: URL, ticket: UploadTicket) async throws {
        var request = request
        request.httpBody = try Data(contentsOf: file)
        state.withLock { _ = $0.running.insert(ticket.id) }
        let outcome: UploadOutcome
        do {
            let (body, response) = try await http.data(for: request)
            outcome = .response(status: response.statusCode, body: body)
        } catch {
            // It may have reached the service before the connection broke; the sender asks before sending again.
            outcome = .noResponse
        }
        state.withLock { state in
            state.running.remove(ticket.id)
            state.finished.append((ticket, outcome))
        }
    }

    public func activeUploads() async -> Set<UploadID> {
        state.withLock { $0.running.union($0.finished.map(\.0.id)) }
    }

    /// The outcomes of `account`'s uploads that finished since the last call, oldest first.
    public func takeOutcomes(of account: AccountID) -> [(UploadID, UploadOutcome)] {
        state.withLock { state in
            let taken = state.finished.filter { $0.0.accountID == account }
            state.finished.removeAll { $0.0.accountID == account }
            return taken.map { ($0.0.id, $0.1) }
        }
    }
}
