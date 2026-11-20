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

    @Test func theChoicesStayOnTheDevice() throws {
        let keys = try Preferences.syncedSettings.flatMap { family -> [String] in
            let scope = try family.local().scope
            return ["cacheLimit", "prefetchScope"].filter { scope.covers($0) }
        }
        #expect(keys.isEmpty)
    }

    @Test func settingsPageOffersThisDevicesChoices() {
        let service = StorageSettings.Service(usage: { .init(messages: 0, attachments: 0) }, trim: { _ in })
        let desktop = StorageSettings(service: service, preferences: StoragePreferences(window: .desktop))
        #expect(desktop.limitChoices == OfflineWindow.desktop.cacheLimitChoices)
        #expect(desktop.limit == 10_000_000_000)
    }
}
