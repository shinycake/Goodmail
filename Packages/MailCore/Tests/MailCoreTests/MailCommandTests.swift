import MailCore
import Testing

/// The command table's keys. UIKit drops a whole menu, without an error, when one of its items repeats keys another
/// item in the menu bar already holds, so a clash here would take a menu out of the Mac's and iPad's menu bar.
struct MailCommandTests {
    @Test("No two commands share keys")
    func distinctKeys() {
        let keyed = MailCommand.allCases.compactMap { command in command.keys.chord.map { (command, $0) } }
        let owners = Dictionary(grouping: keyed, by: \.1).filter { $0.value.count > 1 }
        #expect(owners.isEmpty, "\(owners.mapValues { $0.map(\.0) })")
    }

    @Test("No command of its own repeats keys a system menu holds", arguments: MailCommand.allCases)
    func clearOfSystemMenus(_ command: MailCommand) {
        guard case .own(let chord) = command.keys else { return }
        #expect(!KeyChord.heldBySystemMenus.contains(chord), "\(command) takes \(chord) from a system menu")
    }

    @Test("A command riding a system item has that item's keys, which a system menu holds")
    func systemItemsHoldTheirKeys() {
        for item in SystemMenuItem.allCases {
            #expect(KeyChord.heldBySystemMenus.contains(item.keys), "\(item)")
        }
    }

    @Test("Every keyed command holds Command, so typing never triggers one", arguments: MailCommand.allCases)
    func usesCommand(_ command: MailCommand) {
        guard let chord = command.keys.chord else { return }
        #expect(chord.modifiers.contains(.command))
    }

    @Test("A letter is written lowercase, with Shift said outright, as UIKit matches keys")
    func lowercaseLetters() {
        let keys = MailCommand.allCases.compactMap(\.keys.chord) + KeyChord.heldBySystemMenus
        for chord in keys {
            guard case .character(let character) = chord.key else { continue }
            #expect(!character.isUppercase, "\(chord)")
        }
    }

    @Test("The keys iPad already had stay as they were")
    func iPadKeysKept() {
        let kept: [MailCommand: KeyChord] = [
            .newMessage: KeyChord(.command, "n"), .getMail: KeyChord([.command, .shift], "n"),
            .reply: KeyChord(.command, "r"), .replyAll: KeyChord([.command, .shift], "r"),
            .forward: KeyChord([.command, .shift], "f"), .archive: KeyChord([.command, .control], "a"),
            .trash: KeyChord(.command, .delete), .markRead: KeyChord([.command, .shift], "u"),
            .star: KeyChord([.command, .shift], "l"), .send: KeyChord([.command, .shift], "d"),
            .previousThread: KeyChord([.command, .control], .upArrow),
            .nextThread: KeyChord([.command, .control], .downArrow), .settings: KeyChord(.command, ","),
            .search: KeyChord([.command, .option], "f"), .newWindow: KeyChord([.command, .option], "n"),
            .closeWindow: KeyChord(.command, "w"),
        ]
        for (command, chord) in kept {
            #expect(command.keys.chord == chord, "\(command)")
        }
    }

    @Test("The reader's Find and Zoom keep Apple's keys, and Search Mail keeps its own")
    func readerKeys() {
        #expect(MailCommand.findInConversation.keys.chord == KeyChord(.command, "f"))
        #expect(MailCommand.findNext.keys.chord == KeyChord(.command, "g"))
        #expect(MailCommand.findPrevious.keys.chord == KeyChord([.command, .shift], "g"))
        #expect(MailCommand.quickLook.keys.chord == KeyChord(.command, "y"))
        #expect(MailCommand.actualSize.keys.chord == KeyChord(.command, "0"))
        #expect(MailCommand.search.keys.chord == KeyChord([.command, .option], "f"))
    }

    @Test("Each answer and category command names what it does")
    func answersAndCategories() {
        #expect(MailCommand.allCases.compactMap(\.answer) == Answer.allCommandOrder)
        #expect(MailCommand.allCases.compactMap(\.category) == InboxCategory.allCases)
    }

    @Test("A menu's sections are listed together, so the menu bar reads them in order")
    func placesGroupedByMenu() {
        let menus = MenuPlace.allCases.map(\.menu)
        let runs = menus.enumerated().filter { $0.offset == 0 || menus[$0.offset - 1] != $0.element }.map(\.element)
        #expect(runs.count == Set(runs).count, "\(runs)")
    }
}

extension Answer {
    /// The answers in the order the Message menu lists them.
    fileprivate static let allCommandOrder: [Answer] = [.reply, .replyAll, .forward, .forwardAsAttachment, .editAsNew]
}
