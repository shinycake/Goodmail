import Foundation
import Testing

@testable import MailCore

struct SettingsMergeTests {
    private static let here = "here"
    private static let there = "there"

    private func stamp(_ seconds: TimeInterval, _ device: String = there) -> SettingStamp {
        SettingStamp(time: Date(timeIntervalSinceReferenceDate: seconds), device: device)
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }

    private func merge(
        local: [String: String], scope: LocalSettings.Scope = .everything, ledger: [String: SyncedEntry] = [:],
        shared: [String: SyncedEntry] = [:], at seconds: TimeInterval = 100
    ) -> SettingsMerge {
        SettingsMerge(
            local: LocalSettings(local.mapValues { data($0) }, scope: scope), ledger: ledger, shared: shared,
            now: stamp(seconds, Self.here), keepingRemovals: 50)
    }

    @Test func aFirstSyncSharesWhatTheCloudDoesNotHaveYet() {
        let result = merge(local: ["undo": "10"])
        #expect(result.apply.isEmpty)
        #expect(result.merged == ["undo": .value(data("10"), stamp(100, Self.here))])
        #expect(result.ledger == result.merged)
    }

    @Test func aDeviceThatNeverSyncedTakesUpTheSharedValueOverItsOwn() {
        let shared: [String: SyncedEntry] = ["undo": .value(data("20"), stamp(5))]
        let result = merge(local: ["undo": "10"], shared: shared)
        #expect(result.apply == ["undo": .set(data("20"))])
        #expect(result.merged == shared)
    }

    @Test func anEditHereSinceTheLastSyncWinsOverAnOlderOneThere() {
        let result = merge(
            local: ["undo": "30"], ledger: ["undo": .value(data("10"), stamp(1))],
            shared: ["undo": .value(data("20"), stamp(50))])
        #expect(result.apply.isEmpty)
        #expect(result.merged == ["undo": .value(data("30"), stamp(100, Self.here))])
    }

    @Test func aNewerEditThereWinsOverAnUnchangedValueHere() {
        let synced = SyncedEntry.value(data("10"), stamp(1))
        let theirs = SyncedEntry.value(data("20"), stamp(50))
        let result = merge(local: ["undo": "10"], ledger: ["undo": synced], shared: ["undo": theirs])
        #expect(result.apply == ["undo": .set(data("20"))])
        #expect(result.ledger == ["undo": theirs])
    }

    @Test func theNewerOfTwoEditsWinsWhicheverDeviceMadeIt() {
        let theirs = SyncedEntry.value(data("20"), stamp(150))
        let result = merge(
            local: ["undo": "30"], ledger: ["undo": .value(data("10"), stamp(1))], shared: ["undo": theirs])
        #expect(result.apply == ["undo": .set(data("20"))])
        #expect(result.merged == ["undo": theirs])
    }

    @Test func editsToDifferentSettingsOnTwoDevicesBothStay() {
        let synced: [String: SyncedEntry] = [
            "undo": .value(data("10"), stamp(1)), "layout": .value(data("classic"), stamp(1)),
        ]
        let result = merge(
            local: ["undo": "30", "layout": "classic"], ledger: synced,
            shared: ["undo": .value(data("10"), stamp(1)), "layout": .value(data("chat"), stamp(50))])
        #expect(result.apply == ["layout": .set(data("chat"))])
        #expect(result.merged["undo"] == .value(data("30"), stamp(100, Self.here)))
    }

    @Test func aSettingRemovedHereIsRemovedEverywhere() {
        let synced = SyncedEntry.value(data("a"), stamp(1))
        let result = merge(local: [:], ledger: ["rule": synced], shared: ["rule": synced])
        #expect(result.apply.isEmpty)
        #expect(result.merged == ["rule": .removed(stamp(100, Self.here))])
    }

    @Test func aRemovalThereRemovesTheSettingHere() {
        let synced = SyncedEntry.value(data("a"), stamp(1))
        let result = merge(local: ["rule": "a"], ledger: ["rule": synced], shared: ["rule": .removed(stamp(60))])
        #expect(result.apply == ["rule": .removed])
    }

    @Test func anEditNewerThanARemovalBringsTheSettingBack() {
        let result = merge(
            local: ["rule": "b"], ledger: ["rule": .value(data("a"), stamp(1))],
            shared: ["rule": .removed(stamp(60))])
        #expect(result.apply.isEmpty)
        #expect(result.merged == ["rule": .value(data("b"), stamp(100, Self.here))])
    }

    @Test func settingsOutsideTheScopeAreLeftAsTheyAreShared() {
        let theirs = SyncedEntry.value(data("Sent from my iPad"), stamp(50))
        let result = merge(
            local: ["mine": "Cheers"], scope: .only(["mine"]), ledger: ["other": theirs], shared: ["other": theirs])
        #expect(result.apply.isEmpty)
        #expect(result.merged["other"] == theirs)
        #expect(result.ledger["other"] == nil)
    }

    @Test func oldRemovalsAreForgotten() {
        let result = merge(local: [:], ledger: ["rule": .removed(stamp(10))], shared: ["rule": .removed(stamp(10))])
        #expect(result.merged.isEmpty)
        #expect(result.ledger.isEmpty)
    }

    @Test func equalTimesAreSettledByDeviceTheSameWayOnBoth() {
        let mine = SyncedEntry.value(data("mine"), stamp(100, "a"))
        let theirs = SyncedEntry.value(data("theirs"), stamp(100, "b"))
        #expect(mine.stamp < theirs.stamp)
    }
}
