import Foundation
public import MailCore

/// How much mail is kept on the device, and how much downloads before it's opened (ADR-007).
///
/// Nonisolated, unlike the other preferences: prefetch reads them off the main actor before each run, and
/// `UserDefaults` is safe from any thread.
extension Preferences {
    /// The cache sizes offered, in bytes.
    /// Round in the decimal units sizes are shown in, so 1 GB doesn't read as 1.07 GB.
    nonisolated public static let cacheLimitChoices = [250, 500, 1000, 2000, 5000].map { $0 * 1_000_000 }
    nonisolated public static let defaultCacheLimit = 1_000_000_000

    /// Where messages download before they're opened.
    nonisolated public static var prefetchScope: PrefetchScope {
        get {
            UserDefaults.standard.string(forKey: prefetchScopeKey).flatMap(PrefetchScope.init(rawValue:)) ?? .default
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: prefetchScopeKey) }
    }

    /// The most the downloaded mail and attachments take, in bytes. A stored size outside the choices, as from an
    /// older build, reads as the standard one.
    nonisolated public static var cacheLimit: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: cacheLimitKey)
            return cacheLimitChoices.contains(stored) ? stored : defaultCacheLimit
        }
        set { UserDefaults.standard.set(newValue, forKey: cacheLimitKey) }
    }

    nonisolated static let prefetchScopeKey = "prefetchScope"
    nonisolated static let cacheLimitKey = "cacheLimit"
}
