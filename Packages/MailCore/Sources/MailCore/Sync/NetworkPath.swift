/// What the connection allows, asked before each download that nobody is waiting for.
public protocol NetworkPath: Sendable {
    var allowance: NetworkAllowance { get }
}

/// How much the connection allows downloading ahead of the reader, least first.
public enum NetworkAllowance: Int, Comparable, Sendable {
    /// Offline, or Low Data Mode: nothing nobody asked for.
    case none
    /// Cellular or a personal hotspot: a little.
    case metered
    /// Wi-Fi or wired: as much as the cache holds.
    case unmetered

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where bodies are downloaded ahead of the reader (ADR-007), the reader's choice in Settings.
public enum PrefetchScope: String, CaseIterable, Codable, Sendable {
    /// On Wi-Fi, the newest threads; on cellular, the newest few.
    case wifiAndCellular
    /// On Wi-Fi only.
    case wifiOnly
    /// Never: a body downloads when its thread opens.
    case never

    public static let `default` = PrefetchScope.wifiAndCellular

    /// How many of an account's newest threads keep their bodies on a connection that allows `allowance`.
    public func threadLimit(on allowance: NetworkAllowance, unmetered: Int, metered: Int) -> Int {
        switch (self, allowance) {
        case (.never, _), (_, .none), (.wifiOnly, .metered): 0
        case (.wifiAndCellular, .metered): metered
        case (.wifiAndCellular, .unmetered), (.wifiOnly, .unmetered): unmetered
        }
    }
}
