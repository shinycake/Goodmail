import Foundation
import MailCore
import Testing

@testable import MailUI

/// The automatic reply loads from the service, saves only what changed, and keeps the reader's edit on a refusal.
@MainActor
struct AutoReplyEditorTests {
    private struct Refused: Error {}
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func editor(
        loaded: AutoReply = AutoReply(message: "Away"), saves: @escaping (AutoReply) throws -> Void = { _ in }
    ) -> AutoReplyEditor {
        AutoReplyEditor(
            service: AutoReplyEditor.Service(hasSubject: true, load: { loaded }, save: { try saves($0) }),
            now: { self.now })
    }

    @Test func loadingStartsTheDraftFromTheService() async {
        let editor = editor()
        await editor.load()
        #expect(editor.state == .editing(saved: AutoReply(message: "Away")))
        #expect(editor.draft.message == "Away")
        #expect(!editor.hasChanges)
    }

    @Test func aLoadThatFailsLeavesNothingToEdit() async {
        let editor = AutoReplyEditor(
            service: AutoReplyEditor.Service(hasSubject: true, load: { throw Refused() }, save: { _ in }))
        await editor.load()
        #expect(editor.state == .loadFailed)
    }

    @Test func savingSendsTheDraftAndMakesItTheSavedReply() async {
        var sent: [AutoReply] = []
        let editor = editor(saves: { sent.append($0) })
        await editor.load()
        editor.isOn = true
        await editor.save()
        #expect(sent.map(\.schedule) == [.on])
        #expect(editor.state == .editing(saved: editor.draft))
    }

    @Test func aRefusedSaveKeepsTheEditAndSaysWhy() async {
        let editor = editor(saves: { _ in throw Refused() })
        await editor.load()
        editor.draft.message = "Back Monday"
        await editor.save()
        #expect(editor.saveError != nil)
        #expect(editor.hasChanges)
    }

    @Test func schedulingStartsTodayForAWeekAndKeepsTheEndAfterTheStart() async {
        let editor = editor()
        await editor.load()
        editor.isOn = true
        editor.isScheduled = true
        let start = Calendar.autoupdatingCurrent.startOfDay(for: now)
        #expect(editor.draft.schedule == .between(DateInterval(start: start, duration: 7 * 86_400)))

        editor.start = start.addingTimeInterval(10 * 86_400)
        #expect(editor.end == editor.start)
        editor.isScheduled = false
        #expect(editor.draft.schedule == .on)
    }
}
