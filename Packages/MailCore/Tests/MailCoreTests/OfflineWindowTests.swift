import Testing

@testable import MailCore

/// What each kind of device keeps offline (ADR-007).
struct OfflineWindowTests {
    private static let day = 86_400.0
    private static let gigabyte = 1_000_000_000

    @Test func aHandheldKeepsWhatItAlwaysDid() {
        let window = OfflineWindow.handheld
        #expect(window.longWindow == 90 * Self.day)
        #expect(window.shortWindow == 30 * Self.day)
        #expect(window.defaultCacheLimit == Self.gigabyte)
        #expect(
            window.cacheLimitChoices == [250_000_000, 500_000_000, Self.gigabyte, 2 * Self.gigabyte, 5 * Self.gigabyte])
    }

    @Test func aDesktopKeepsAYearOfHeadersAndTenGigabytes() {
        let window = OfflineWindow.desktop
        #expect(window.longWindow == 365 * Self.day)
        #expect(window.shortWindow == 90 * Self.day)
        #expect(window.defaultCacheLimit == 10 * Self.gigabyte)
        #expect(window.cacheLimitChoices.last == 50 * Self.gigabyte)
    }

    @Test(arguments: [OfflineWindow.handheld, .desktop])
    func theDefaultIsOneOfTheChoices(window: OfflineWindow) {
        #expect(window.cacheLimitChoices.contains(window.defaultCacheLimit))
        #expect(window.cacheLimitChoices == window.cacheLimitChoices.sorted())
    }

    @Test(arguments: [OfflineWindow.handheld, .desktop])
    func aChoiceStoredHereIsKept(window: OfflineWindow) {
        for choice in window.cacheLimitChoices { #expect(window.cacheLimit(stored: choice) == choice) }
    }

    @Test(arguments: [OfflineWindow.handheld, .desktop])
    func nothingStoredOrOneOutsideTheChoicesReadsAsTheDefault(window: OfflineWindow) {
        #expect(window.cacheLimit(stored: nil) == window.defaultCacheLimit)
        #expect(window.cacheLimit(stored: 0) == window.defaultCacheLimit)
        #expect(window.cacheLimit(stored: 123) == window.defaultCacheLimit)
    }

    @Test func aHandheldChoiceTooBigForItsOwnListIsRefusedButOneBothShareIsKept() {
        #expect(OfflineWindow.handheld.cacheLimit(stored: 10 * Self.gigabyte) == Self.gigabyte)
        #expect(OfflineWindow.desktop.cacheLimit(stored: Self.gigabyte) == Self.gigabyte)
    }

    @Test func theHeadOfTheInboxLooksBackAsAHandheldDoes() {
        #expect(SyncScope.inboxHead(limit: 10).offlineWindow == .handheld)
        #expect(SyncScope.window(.desktop).offlineWindow == .desktop)
    }
}
