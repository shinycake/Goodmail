import FieldDiagnostics
import Foundation
import Testing

/// Debug builds launched with `-GoodmailSeedDiagnostics <folder>` fill the archive from these fixtures, for the UI
/// test and screenshots of Settings > Diagnostics. They are deliveries as JSON, with ISO 8601 dates, so they must keep
/// decoding as the types change.
struct FixtureTests {
    @Test func theFixturesDecodeAsDeliveries() throws {
        let folder = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let deliveries = try files.map { try decoder.decode(Delivery.self, from: Data(contentsOf: $0)) }
        #expect(deliveries.count == 5)
        let events = deliveries.compactMap { delivery -> DiagnosticEvent? in
            guard case .event(let event) = delivery.content else { return nil }
            return event
        }
        #expect(events.contains(.crash(Crash(exceptionType: 1, signal: 11, reason: "Namespace SIGNAL, Code 11"))))
        #expect(events.contains(.hang(duration: 2.4)))
        #expect(deliveries.allSatisfy { !$0.raw.isEmpty })
    }
}
