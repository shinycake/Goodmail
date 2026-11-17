import Testing
import UIKit

@testable import MailUI

@Suite("Keyboard shortcuts")
struct KeyboardShortcutTests {
    @Test("No two shortcuts share keys")
    func distinctKeys() {
        let keys = KeyboardShortcut.allCases.map { "\($0.modifiers.rawValue)-\($0.input)" }
        #expect(Set(keys).count == keys.count)
    }

    @Test("Every shortcut uses Command, so typing never triggers one", arguments: KeyboardShortcut.allCases)
    func usesCommand(_ shortcut: KeyboardShortcut) {
        #expect(shortcut.modifiers.contains(.command))
    }

    @Test("Every shortcut has a name for the list Command shows", arguments: KeyboardShortcut.allCases)
    @MainActor
    func named(_ shortcut: KeyboardShortcut) {
        #expect(!shortcut.title.isEmpty)
    }
}
