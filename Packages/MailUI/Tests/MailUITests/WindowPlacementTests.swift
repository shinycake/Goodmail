import MailCore
import Testing

@testable import MailUI

@MainActor @Suite struct WindowPlacementTests {
    private let thread = ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t")

    @Test(arguments: [
        (InteractionStyle.touch, ComposePlacement.sheet, SettingsPlacement.cover),
        (.desktop, .ownWindow, .ownWindow),
    ])
    func `a desktop gives new messages and Settings windows of their own`(
        style: InteractionStyle, compose: ComposePlacement, settings: SettingsPlacement
    ) {
        #expect(style.composePlacement == compose)
        #expect(style.settingsPlacement == settings)
    }

    @Test func `a thread opened in a new window is the reader alone on a desktop`() {
        #expect(InteractionStyle.desktop.threadWindowLayout == .message)
        #expect(InteractionStyle.touch.threadWindowLayout == .viewer)
    }

    @Test func `a touch window is always a viewer, even restoring a Mac's message window`() {
        let message = WindowState().opening(thread, in: .inbox, as: .message)
        #expect(InteractionStyle.touch.laying(out: message).layout == .viewer)
        #expect(InteractionStyle.touch.laying(out: message).openThread?.id == thread, "the thread stays open")
        #expect(InteractionStyle.desktop.laying(out: message) == message)
    }
}
