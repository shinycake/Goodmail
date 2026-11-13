import Foundation
import MailCore
import Synchronization

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A background session in memory. Uploads stay under way until the test finishes them against the fake server,
/// or loses them as a killed launch would.
final class FakeUploads: UploadTransport {
    struct Upload {
        let request: URLRequest
        let file: URL
        let ticket: UploadTicket
    }

    private struct State {
        var active: [UploadID: Upload] = [:]
        var started: [Upload] = []
        var failUpload: (any Error)?
    }

    private let server: FakeMailServer
    private let state = Mutex(State())

    init(server: FakeMailServer) {
        self.server = server
    }

    func upload(_ request: URLRequest, from file: URL, ticket: UploadTicket) async throws {
        try state.withLock { state in
            if let failure = state.failUpload { throw failure }
            let upload = Upload(request: request, file: file, ticket: ticket)
            state.active[ticket.id] = upload
            state.started.append(upload)
        }
    }

    func activeUploads() async -> Set<UploadID> {
        state.withLock { Set($0.active.keys) }
    }

    /// Every upload ever started, in order.
    var started: [Upload] { state.withLock(\.started) }

    /// Runs every upload under way against the server, and returns their outcomes for `Sender.complete`.
    func finishAll() throws -> [(UploadID, UploadOutcome)] {
        let uploads = state.withLock { state in
            defer { state.active = [:] }
            return state.active.values.sorted { $0.file.path < $1.file.path }
        }
        return try uploads.map { upload in
            (upload.ticket.id, server.receive(upload.request, body: try Data(contentsOf: upload.file)))
        }
    }

    /// Drops every upload under way without an outcome, as when the launch that would hear it is gone.
    func loseAll() {
        state.withLock { $0.active = [:] }
    }

    func failUpload(with error: (any Error)?) {
        state.withLock { $0.failUpload = error }
    }
}
