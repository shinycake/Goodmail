import Foundation

/// A domain's BIMI record, `v=BIMI1; l=<logo URL>; a=<certificate URL>`, published as a DNS TXT record at
/// `default._bimi.<domain>`. It names the square SVG logo that mail clients show beside the domain's mail.
public struct BIMIRecord: Sendable, Equatable {
    /// The logo, or `nil` when the domain says it has none to show (an empty `l=`).
    public let logo: URL?

    /// The record among a name's TXT records: `nil` when none is a BIMI record, or when more than one is, which the
    /// specification treats as no record.
    public init?(txtRecords: [String]) {
        let records = txtRecords.compactMap(Self.tags)
        guard records.count == 1, let tags = records.first else { return nil }
        let location = tags["l"]?.split(separator: ",").first.map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        // Logos are only ever fetched over HTTPS.
        logo = location.flatMap(URL.init(string:)).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
    }

    /// The record's tags, or `nil` for a TXT record that isn't BIMI. `v=BIMI1` must come first.
    private static func tags(_ record: String) -> [String: String]? {
        var tags: [String: String] = [:]
        for (position, part) in record.split(separator: ";").enumerated() {
            let pair = part.split(separator: "=", maxSplits: 1)
            let name = pair.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let value = pair.count == 2 ? pair[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if position == 0 {
                guard name == "v", value == "BIMI1" else { return nil }
            }
            if !name.isEmpty { tags[name] = value }
        }
        return tags.isEmpty ? nil : tags
    }

    /// A TXT record's text from its wire form: length-prefixed strings, which a long record splits at 255 bytes and
    /// a reader joins back together. `nil` when a length runs past the end.
    public static func text(ofTXTRecordData data: [UInt8]) -> String? {
        var bytes: [UInt8] = []
        var index = 0
        while index < data.count {
            let length = Int(data[index])
            let end = index + 1 + length
            guard end <= data.count else { return nil }
            bytes += data[(index + 1)..<end]
            index = end
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
