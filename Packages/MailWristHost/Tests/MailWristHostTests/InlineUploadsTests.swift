import Foundation
import MailCore
import Testing

@testable import MailWristHost

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A Gmail send from the watch is uploaded while the app waits, and its outcome kept for the sender.
struct InlineUploadsTests {
    private let file = FileManager.default.temporaryDirectory.appending(path: "InlineUploadsTests-\(UUID().uuidString)")
    private let request = URLRequest(url: URL(string: "https://gmail.example/upload")!)
    private let ticket = UploadTicket(accountID: AccountID(rawValue: "g"), id: UploadID())

    init() throws {
        try Data("raw message".utf8).write(to: file)
    }

    @Test func anAnsweredUploadKeepsItsResponseUntilTaken() async throws {
        let uploads = InlineUploads(http: Answering(status: 200))

        try await uploads.upload(request, from: file, ticket: ticket)

        #expect(await uploads.activeUploads() == [ticket.id], "not settled before its outcome is taken in")
        let outcomes = uploads.takeOutcomes(of: ticket.accountID)
        #expect(outcomes.map(\.0) == [ticket.id])
        #expect(outcomes.map(\.1) == [.response(status: 200, body: Data("raw message".utf8))])
        #expect(uploads.takeOutcomes(of: ticket.accountID).isEmpty)
        #expect(await uploads.activeUploads().isEmpty)
    }

    @Test func aBrokenConnectionEndsWithoutAResponse() async throws {
        let uploads = InlineUploads(http: Answering(status: nil))

        try await uploads.upload(request, from: file, ticket: ticket)

        #expect(uploads.takeOutcomes(of: ticket.accountID).map(\.1) == [.noResponse])
    }
}

/// Answers with `status` and echoes the body, or fails like a dropped connection when `status` is `nil`.
private struct Answering: HTTPClient {
    let status: Int?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let status else { throw URLError(.networkConnectionLost) }
        return (
            request.httpBody ?? Data(),
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}
