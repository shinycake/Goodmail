import Foundation
import MailCore
import Testing

@testable import MailUI

/// An Other Mail Account's servers load from the device, and a change is kept only once both servers accept it.
@MainActor
struct ServerSettingsEditorTests {
    private struct Missing: Error {}

    private let stored = ServerSettingsEditor.Login(
        settings: MailServerSettings(
            imap: MailServer(host: "imap.example.com", port: 993, security: .tls),
            smtp: MailServer(host: "smtp.example.com", port: 587, security: .startTLS),
            username: "dana@example.com"),
        password: "secret")

    private func editor(saves: @escaping (ServerSettingsEditor.Login) throws -> Void = { _ in })
        -> ServerSettingsEditor
    {
        ServerSettingsEditor(
            service: ServerSettingsEditor.Service(kind: .servers, load: { stored }, save: { try saves($0) }))
    }

    @Test func loadingStartsTheDraftFromTheStoredLogin() {
        let editor = editor()
        editor.load()
        #expect(editor.state == .editing(saved: stored, failure: nil))
        #expect(editor.draft == stored)
        #expect(!editor.canSave)
    }

    @Test func aMissingLoginLeavesNothingToEdit() {
        let editor = ServerSettingsEditor(
            service: ServerSettingsEditor.Service(kind: .servers, load: { throw Missing() }, save: { _ in }))
        editor.load()
        #expect(editor.state == .loadFailed)
    }

    @Test func aChangeIsCheckedThenKept() async {
        var saved: [ServerSettingsEditor.Login] = []
        let editor = editor(saves: { saved.append($0) })
        editor.load()
        editor.draft.settings?.imap.host = "mail.example.com"
        #expect(editor.canSave)
        editor.submit()
        #expect(editor.isSaving)
        // Edits made while the check runs aren't what it checks.
        editor.draft.settings?.imap.host = "typo"
        await editor.save()
        #expect(saved.map(\.settings?.imap.host) == ["mail.example.com"])
        #expect(editor.state == .saved)
    }

    @Test func anIncompleteDraftCantBeSaved() {
        let editor = editor()
        editor.load()
        editor.draft.settings?.smtp.host = ""
        #expect(!editor.canSave)
        editor.draft = stored
        editor.draft.password = ""
        #expect(!editor.canSave)
        editor.submit()
        #expect(editor.state == .editing(saved: stored, failure: nil))
    }

    @Test func aRefusedPasswordIsClearedAndTheStoredLoginKept() async {
        let editor = editor(saves: { _ in throw OtherAccountSignInFailure.refused(.incoming) })
        editor.load()
        editor.draft.password = "wrong"
        editor.submit()
        await editor.save()
        #expect(editor.state == .editing(saved: stored, failure: .signIn(.refused(.incoming))))
        #expect(editor.draft.password.isEmpty)
        #expect(editor.draft.settings == stored.settings)
    }

    @Test func anUnreachableServerKeepsTheEditToCorrect() async {
        let editor = editor(saves: { _ in throw OtherAccountSignInFailure.unreachable(.outgoing) })
        editor.load()
        editor.draft.settings?.smtp.port = 2525
        editor.submit()
        await editor.save()
        #expect(editor.failure == .signIn(.unreachable(.outgoing)))
        #expect(editor.draft.settings?.smtp.port == 2525)
        #expect(editor.canSave)
    }

    @Test func iCloudsAppPasswordIsAllThereIsToEdit() async {
        var saved: [ServerSettingsEditor.Login] = []
        let editor = ServerSettingsEditor(
            service: ServerSettingsEditor.Service(
                kind: .appPassword, load: { ServerSettingsEditor.Login(settings: nil, password: "abcd-efgh") },
                save: { saved.append($0) }))
        editor.load()
        #expect(!editor.canSave)
        editor.draft.password = "wxyz-wxyz"
        #expect(editor.canSave)
        editor.submit()
        await editor.save()
        #expect(saved == [ServerSettingsEditor.Login(settings: nil, password: "wxyz-wxyz")])
        #expect(editor.state == .saved)
    }
}
