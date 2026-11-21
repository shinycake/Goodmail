import MailCore
import Testing

@testable import MailUI

@MainActor struct DesktopSettingsTests {
    private final class FakeLoginItem: LoginItemService {
        var status: LoginItemStatus
        var failure: (any Error)?
        private(set) var opened = false

        init(_ status: LoginItemStatus) { self.status = status }

        func register() throws {
            if let failure { throw failure }
            status = .enabled
        }

        func unregister() throws {
            if let failure { throw failure }
            status = .notRegistered
        }

        func openSettings() { opened = true }
    }

    private struct Refused: Error {}

    @Test func turningOnRegistersAndShowsTheSystemsAnswer() {
        let item = FakeLoginItem(.notRegistered)
        let settings = DesktopSettings(loginItem: item)
        settings.setOpensAtLogin(true)
        #expect(settings.openAtLogin == .on)
        settings.setOpensAtLogin(false)
        #expect(settings.openAtLogin == .off)
    }

    @Test func aLoginItemThatNeedsApprovalIsShownAsSuch() {
        let item = FakeLoginItem(.requiresApproval)
        let settings = DesktopSettings(loginItem: item)
        #expect(settings.openAtLogin == .needsApproval)
        settings.openLoginItemsSettings()
        #expect(item.opened)
    }

    @Test func aRefusalShowsAsFailedUntilTheStatusIsReadAgain() {
        let item = FakeLoginItem(.notRegistered)
        item.failure = Refused()
        let settings = DesktopSettings(loginItem: item)
        settings.setOpensAtLogin(true)
        guard case .failed = settings.openAtLogin else {
            Issue.record("expected a failure")
            return
        }
        settings.refresh()
        #expect(settings.openAtLogin == .off)
    }
}
