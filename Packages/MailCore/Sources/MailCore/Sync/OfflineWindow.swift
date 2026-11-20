public import Foundation

/// How much mail a device keeps offline and how much space the downloaded bodies may take (ADR-007). It depends on
/// the kind of device, which the app decides once at its edge: a phone or tablet is short of space, a Mac isn't.
public enum OfflineWindow: Equatable, Sendable {
    /// iPhone and iPad.
    case handheld
    /// A Mac.
    case desktop

    /// Labels whose headers are kept for `longWindow`; every other label keeps `shortWindow`.
    public static let longWindowLabels = ["INBOX", "SENT", "STARRED", "DRAFT"]

    /// How far back the headers of `longWindowLabels` are kept.
    public var longWindow: TimeInterval {
        switch self {
        case .handheld: 90 * 86_400
        case .desktop: 365 * 86_400
        }
    }

    /// How far back the headers of every other label are kept.
    public var shortWindow: TimeInterval {
        switch self {
        case .handheld: 30 * 86_400
        case .desktop: 90 * 86_400
        }
    }

    /// The cache sizes the reader may choose, in bytes, smallest first.
    /// Round in the decimal units sizes are shown in, so 1 GB doesn't read as 1.07 GB.
    public var cacheLimitChoices: [Int] {
        let megabytes =
            switch self {
            case .handheld: [250, 500, 1_000, 2_000, 5_000]
            case .desktop: [1_000, 5_000, 10_000, 20_000, 50_000]
            }
        return megabytes.map { $0 * 1_000_000 }
    }

    /// The cache size before the reader chooses one.
    public var defaultCacheLimit: Int {
        switch self {
        case .handheld: 1_000_000_000
        case .desktop: 10_000_000_000
        }
    }

    /// The size a stored choice means here. One outside the choices, as from an older build or another kind of
    /// device, reads as the default.
    public func cacheLimit(stored: Int?) -> Int {
        stored.flatMap { cacheLimitChoices.contains($0) ? $0 : nil } ?? defaultCacheLimit
    }
}
