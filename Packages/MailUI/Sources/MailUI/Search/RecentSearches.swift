import Foundation

/// What the reader searched for lately, newest first, kept on this device.
public struct RecentSearches {
    static let limit = 8
    private let defaults: UserDefaults
    private let key = "recentSearches"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var all: [String] { defaults.stringArray(forKey: key) ?? [] }

    /// Puts `text` first, once, whatever its case was before.
    public func record(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let rest = all.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        defaults.set(Array(([text] + rest).prefix(Self.limit)), forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
