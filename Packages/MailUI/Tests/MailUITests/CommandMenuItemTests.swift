import MailCore
import Testing
import UIKit

@testable import MailUI

/// How a menu bar item shows what the window would do with its command now.
@Suite("Command menu item")
@MainActor
struct CommandMenuItemTests {
    @Test("A ready command is enabled, under the title and check its screen gives")
    func readyIsEnabled() {
        let item = MailCommand.markRead.menuItem(nil, action: #selector(UIResponder.copy(_:)))
        item.attributes = .disabled
        item.show(.ready(perform: {}, title: "Mark as Unread", isOn: true), as: .markRead)
        #expect(!item.attributes.contains(.disabled))
        #expect(item.title == "Mark as Unread")
        #expect(item.state == .on)
    }

    @Test(
        "A command nobody can do now is dimmed under its own title", arguments: [CommandAnswer.unavailable, .notHere])
    func otherwiseDimmed(answer: CommandAnswer) {
        let item = MailCommand.zoomIn.menuItem(nil, action: #selector(UIResponder.copy(_:)))
        item.title = "Something else"
        item.state = .on
        item.show(answer, as: .zoomIn)
        #expect(item.attributes.contains(.disabled))
        #expect(item.title == MailCommand.zoomIn.title)
        #expect(item.state == .off)
    }

    @Test("A refusal dims the item under the title it gives")
    func refusalNamesItself() {
        let item = MailCommand.move.menuItem(nil, action: #selector(UIResponder.copy(_:)))
        item.show(.refused(title: "Move to Inbox"), as: .move)
        #expect(item.attributes.contains(.disabled))
        #expect(item.title == "Move to Inbox")
    }

    @Test("A sidebar number with no row goes from the menu, and comes back once it has one")
    func rowNumberWithoutRowHides() {
        let item = MailCommand.goTo9.menuItem(nil, action: #selector(UIResponder.copy(_:)))
        item.show(.notHere, as: .goTo9)
        #expect(item.attributes.contains(.hidden))
        item.show(.ready(perform: {}), as: .goTo9)
        #expect(!item.attributes.contains(.hidden))
        #expect(!item.attributes.contains(.disabled))
    }
}
