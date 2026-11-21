import MailCore
import Testing

/// Where the File and Mailbox menus list Goodmail's commands, as Apple Mail lists them.
struct MenuOrderTests {
    private func commands(in menu: MenuBarMenu) -> [MailCommand] {
        MailCommand.allCases.filter { $0.place.menu == menu }
    }

    @Test("File opens with New Message on ⌘N, then New Viewer Window on ⌥⌘N, then Open in New Window")
    func fileOpensWithNewMessage() {
        #expect(Array(commands(in: .file).prefix(3)) == [.newMessage, .newWindow, .openInNewWindow])
        #expect(MailCommand.newMessage.keys == .own(KeyChord(.command, "n")))
        #expect(MailCommand.newWindow.keys.chord == KeyChord([.command, .option], "n"))
    }

    @Test("Mailbox lists Get New Mail, then New Label, then Erase Trash")
    func mailboxOrder() throws {
        let mailbox = commands(in: .mailbox)
        let order = try [MailCommand.getMail, .newLabel, .eraseTrash].map { try #require(mailbox.firstIndex(of: $0)) }
        #expect(order == order.sorted())
    }

    @Test("New Label stands apart from fetching and erasing, has no keys, and stays out of the toolbar")
    func newLabelPlace() {
        #expect(MailCommand.newLabel.place != MailCommand.getMail.place)
        #expect(MailCommand.newLabel.place != MailCommand.eraseTrash.place)
        #expect(MailCommand.newLabel.keys == .none)
        #expect(!MailCommand.newLabel.mayShowInToolbar)
    }
}
