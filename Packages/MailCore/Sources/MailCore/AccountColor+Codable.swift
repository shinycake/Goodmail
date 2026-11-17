import Foundation

/// An account color travels as its stored form, `rawValue`, as it does to the database.
extension AccountColor: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let color = AccountColor(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\(raw) is neither an offered color nor a hex color")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
