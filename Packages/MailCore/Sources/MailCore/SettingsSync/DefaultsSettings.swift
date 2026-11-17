import Foundation

/// Settings kept in `UserDefaults`, one element per key, each shared as JSON.
public struct DefaultsValues: SettingsFamily {
    public let name: String
    private let keys: [String]
    /// The defaults' suite, `nil` for the standard ones. Kept by name, since `UserDefaults` isn't `Sendable` everywhere.
    private let suite: String?

    public init(name: String, keys: [String], suite: String? = nil) {
        self.name = name
        self.keys = keys
        self.suite = suite
    }

    public func local() throws -> LocalSettings {
        var values: [String: Data] = [:]
        for key in keys {
            guard let object = defaults.object(forKey: key) else { continue }
            values[key] = try JSONValue.data(of: object)
        }
        return LocalSettings(values, scope: .only(Set(keys)))
    }

    public func apply(_ changes: [String: SettingChange]) throws {
        for (key, change) in changes {
            switch change {
            case .set(let data): defaults.set(try JSONValue.object(in: data), forKey: key)
            case .removed: defaults.removeObject(forKey: key)
            }
        }
    }
}

/// A list kept under one `UserDefaults` key, shared as a set of its items: two devices adding at once keep both.
/// Items taken up from another device go at the end.
public struct DefaultsList: SettingsFamily {
    /// How the list is stored.
    public enum Storage: Sendable {
        /// As an array of strings.
        case strings
        /// As a JSON array, in `Data`.
        case json
    }

    public let name: String
    private let key: String
    private let storage: Storage
    /// The defaults' suite, `nil` for the standard ones. Kept by name, since `UserDefaults` isn't `Sendable` everywhere.
    private let suite: String?

    public init(name: String, key: String, storage: Storage, suite: String? = nil) {
        self.name = name
        self.key = key
        self.storage = storage
        self.suite = suite
    }

    public func local() throws -> LocalSettings {
        LocalSettings(Dictionary(try items().map { ($0, Data($0.utf8)) }, uniquingKeysWith: { first, _ in first }))
    }

    public func apply(_ changes: [String: SettingChange]) throws {
        var items = try items().filter { changes[$0] == nil }
        items += changes.compactMap { item, change in change == .removed ? nil : item }.sorted()
        switch storage {
        case .strings: defaults.set(items, forKey: key)
        case .json: defaults.set(Data("[\(items.joined(separator: ","))]".utf8), forKey: key)
        }
    }

    /// Each item, as its element: the string itself, or the item's JSON.
    private func items() throws -> [String] {
        switch storage {
        case .strings:
            return defaults.stringArray(forKey: key) ?? []
        case .json:
            guard let data = defaults.data(forKey: key) else { return [] }
            let array = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [Any] ?? []
            return try array.map { String(decoding: try JSONValue.data(of: $0), as: UTF8.self) }
        }
    }
}

extension DefaultsValues {
    private var defaults: UserDefaults { suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard }
}

extension DefaultsList {
    private var defaults: UserDefaults { suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard }
}

/// A property-list value as JSON with sorted keys, so the same value always reads the same.
enum JSONValue {
    static func data(of object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }

    static func object(in data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }
}
