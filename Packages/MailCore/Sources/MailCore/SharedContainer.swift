import Foundation

/// Identifiers shared by the app and its extensions (ADR-002).
public enum SharedContainer {
    public static let appGroupID = "group.com.idanbirman.goodmail"

    /// Without the team prefix, which the Keychain adds from the entitlement.
    public static let keychainGroupSuffix = "com.idanbirman.goodmail.shared"

    /// The App Group directory, or `nil` when the process lacks the entitlement (e.g. unit tests).
    public static var directoryURL: URL? {
        #if canImport(Darwin)
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        #else
            nil  // Linux test builds have no App Groups.
        #endif
    }
}
