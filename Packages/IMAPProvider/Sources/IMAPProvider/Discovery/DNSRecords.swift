import Foundation
import MailCore

/// DNS records read over HTTPS (Google's JSON resolver, which Thunderbird's MX lookup also asks), since iOS has no
/// public API that returns MX or SRV records. Only domain names go to the resolver, never an address.
struct DNSRecords: Sendable {
    /// The body at a URL when it answers 200, else `nil`.
    let fetch: @Sendable (URL) async throws -> Data?

    /// The domain's mail exchangers, most preferred first; none when it has no MX records or the lookup fails.
    func mailExchangers(of domain: String) async -> [String] {
        await answers(for: domain, type: .mx)
            .compactMap(MailExchanger.init(data:))
            .sorted { $0.preference < $1.preference }
            .map(\.host)
    }

    /// The servers a domain names for a service (RFC 2782), best first: lowest priority, then highest weight. A
    /// lone record whose target is `.` says the domain doesn't offer the service, and leaves none.
    func services(_ name: String) async -> [ServiceRecord] {
        await answers(for: name, type: .srv)
            .compactMap(ServiceRecord.init(data:))
            .filter { !$0.host.isEmpty }
            .sorted { ($0.priority, -Int($0.weight)) < ($1.priority, -Int($1.weight)) }
    }

    enum RecordType: Int, Sendable {
        case mx = 15
        case srv = 33
    }

    /// The `data` of each answer of `type`, as the resolver writes it; none when the lookup fails.
    private func answers(for name: String, type: RecordType) async -> [String] {
        var components = URLComponents(string: "https://dns.google/resolve")
        components?.queryItems = [
            URLQueryItem(name: "name", value: name), URLQueryItem(name: "type", value: String(type.rawValue)),
        ]
        guard let url = components?.url, let data = try? await fetch(url),
            let response = try? JSONDecoder().decode(Response.self, from: data), response.status == 0
        else { return [] }
        return (response.answer ?? []).filter { $0.type == type.rawValue }.map(\.data)
    }

    /// The resolver's answer: `Status` 0 is NOERROR.
    private struct Response: Decodable {
        struct Answer: Decodable {
            let type: Int
            let data: String
        }

        let status: Int
        let answer: [Answer]?

        enum CodingKeys: String, CodingKey {
            case status = "Status"
            case answer = "Answer"
        }
    }
}

/// An MX record: `10 mx.example.com.`
struct MailExchanger: Equatable {
    var preference: Int
    var host: String

    init?(data: String) {
        let fields = data.split(separator: " ")
        guard fields.count == 2, let preference = Int(fields[0]) else { return nil }
        self.preference = preference
        host = hostName(fields[1])
        guard !host.isEmpty else { return nil }
    }
}

/// An SRV record: `0 1 993 imap.example.com.` (priority, weight, port, target).
struct ServiceRecord: Equatable, Sendable {
    var priority: Int
    var weight: UInt16
    var port: UInt16
    /// Empty for the target `.`, which means the service isn't offered.
    var host: String

    init(priority: Int, weight: UInt16, port: UInt16, host: String) {
        self.priority = priority
        self.weight = weight
        self.port = port
        self.host = host
    }

    init?(data: String) {
        let fields = data.split(separator: " ")
        guard fields.count == 4, let priority = Int(fields[0]), let weight = UInt16(fields[1]),
            let port = UInt16(fields[2])
        else { return nil }
        self.init(priority: priority, weight: weight, port: port, host: hostName(fields[3]))
    }
}

/// A host name without its trailing root dot, in lower case.
private func hostName(_ name: Substring) -> String {
    (name.hasSuffix(".") ? name.dropLast() : name).lowercased()
}

extension ServiceRecord {
    func server(_ security: MailServer.Security) -> MailServer {
        MailServer(host: host, port: port, security: security)
    }
}
