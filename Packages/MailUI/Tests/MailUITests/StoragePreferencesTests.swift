import Foundation
import MailCore
import Testing

@testable import MailUI

/// The storage choices belong to the device (ADR-024) and suit its kind (ADR-007).
@Suite(.serialized)
@MainActor
struct StoragePreferencesTests {
    init() {
        UserDefaults.standard.removeObject(forKey: StoragePreferences.cacheLimitKey)
        UserDefaults.standard.removeObject(forKey: StoragePreferences.prefetchScopeKey)
    }

    @Test func eachKindOfDeviceStartsFromItsOwnDefault() {
        #expect(StoragePreferences(window: .handheld).cacheLimit == 1_000_000_000)
        #expect(StoragePreferences(window: .desktop).cacheLimit == 10_000_000_000)
        #expect(StoragePreferences(window: .desktop).prefetchScope == .default)
    }

    @Test func aValueStoredBeforeTheChoicesMovedIsKept() {
        UserDefaults.standard.set(5_000_000_000, forKey: "cacheLimit")
        UserDefaults.standard.set("wifiOnly", forKey: "prefetchScope")
        let preferences = StoragePreferences(window: .handheld)
        #expect(preferences.cacheLimit == 5_000_000_000)
        #expect(preferences.prefetchScope == .wifiOnly)
    }

    @Test func aChoiceTheOtherKindOfDeviceOffersReadsAsTheDefault() {
        UserDefaults.standard.set(50_000_000_000, forKey: "cacheLimit")
        #expect(StoragePreferences(window: .handheld).cacheLimit == 1_000_000_000)
        #expect(StoragePreferences(window: .desktop).cacheLimit == 50_000_000_000)
    }

    /// A list family has no keys of its own to leave out, since it shares the items of one list, so what matters is
    /// that no family reads these two keys, whatever it says it covers.
    @Test func theChoicesStayOnTheDevice() throws {
        let choices = [StoragePreferences.cacheLimitKey, StoragePreferences.prefetchScopeKey]
        UserDefaults.standard.set(5_000_000_000, forKey: StoragePreferences.cacheLimitKey)
        UserDefaults.standard.set("wifiOnly", forKey: StoragePreferences.prefetchScopeKey)
        let shared = try Preferences.syncedSettings.flatMap { family in
            try family.local().values.keys.filter(choices.contains)
        }
        #expect(shared.isEmpty)
    }

    @Test func settingsPageOffersThisDevicesChoices() {
        let service = StorageSettings.Service(usage: { .init(messages: 0, attachments: 0) }, trim: { _ in })
        let desktop = StorageSettings(service: service, preferences: StoragePreferences(window: .desktop))
        #expect(desktop.limitChoices == OfflineWindow.desktop.cacheLimitChoices)
        #expect(desktop.limit == 10_000_000_000)
    }
}
