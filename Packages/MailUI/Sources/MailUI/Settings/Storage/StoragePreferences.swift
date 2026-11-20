import Foundation
public import MailCore

/// How much mail is kept on this device, and how much downloads before it's opened (ADR-007). Choices of this device
/// alone: they aren't in `Preferences.syncedSettings` (ADR-024), since a Mac's room says nothing of an iPhone's.
///
/// Nonisolated, unlike the other preferences: prefetch reads them off the main actor before each run, and
/// `UserDefaults` is safe from any thread. The keys are the ones the choices were first stored under, so each device
/// keeps the value it has.
nonisolated public struct StoragePreferences: Sendable {
    /// The kind of device, which decides what is on offer.
    public let window: OfflineWindow

    public init(window: OfflineWindow) {
        self.window = window
    }

    /// Where messages download before they're opened.
    public var prefetchScope: PrefetchScope {
        get {
            UserDefaults.standard.string(forKey: Self.prefetchScopeKey).flatMap(PrefetchScope.init(rawValue:))
                ?? .default
        }
        nonmutating set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.prefetchScopeKey) }
    }

    /// The most the downloaded mail and attachments take, in bytes: one of this device's choices.
    public var cacheLimit: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: Self.cacheLimitKey) as? Int
            return window.cacheLimit(stored: stored)
        }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.cacheLimitKey) }
    }

    static let prefetchScopeKey = "prefetchScope"
    static let cacheLimitKey = "cacheLimit"
}
