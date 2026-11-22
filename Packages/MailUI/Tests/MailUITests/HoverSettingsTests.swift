import Foundation
import MailCore
import Testing

@testable import MailUI

/// The hover actions setting: kept on this device, and shared with the reader's others like the swipes.
@Suite(.serialized)
@MainActor
struct HoverSettingsTests {
    private let keys = [Preferences.showsHoverActionsKey, Preferences.hoverActionsKey]

    private func reset() {
        for key in keys { Preferences.defaults.removeObject(forKey: key) }
    }

    @Test func neverSetItShowsTheStandardActions() {
        reset()
        defer { reset() }
        #expect(Preferences.hoverActions == .standard)
    }

    @Test func turningThemOffAndOnBringsBackThePicks() {
        reset()
        defer { reset() }
        let picks = HoverActions.Picks([.star, .snooze])
        Preferences.hoverActions = .on(picks)
        Preferences.hoverActions = .off
        #expect(Preferences.hoverActions == .off)
        #expect(Preferences.hoverActionPicks == picks, "kept while off")
    }

    @Test(arguments: [HoverActions.on(HoverActions.Picks([.star, .read])), .off, .on(HoverActions.Picks([]))])
    func theSettingReachesAnotherDeviceAsItWasSet(_ setting: HoverActions) throws {
        reset()
        defer { reset() }
        let synced = try #require(Preferences.syncedSettings.first { $0.name == Preferences.syncedGroup })
        Preferences.hoverActions = setting
        let sent = try synced.local().values.filter { keys.contains($0.key) }
        // The other device starts from nothing and takes up what this one shared.
        reset()
        try synced.apply(sent.mapValues(SettingChange.set))
        #expect(Preferences.hoverActions == setting)
    }
}
