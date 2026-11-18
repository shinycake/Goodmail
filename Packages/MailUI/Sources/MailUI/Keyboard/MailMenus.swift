public import UIKit

/// The app's commands in the iPadOS menu bar, which also lists them while Command is held: New Message and New Window
/// in File, Settings in the app's menu, and Mailbox and Message menus as in Apple Mail. Every command performs through
/// `action` on the window, which enables only what the screens on show answer (`KeyboardShortcuts`).
@MainActor
public enum MailMenus {
    /// Whether the menu bar carries the commands, as on iPad. Elsewhere the window offers them as key commands of its
    /// own, so a keyboard reaches them on iPhone too.
    public static var inMenuBar: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    public static func build(_ builder: any UIMenuBuilder, action: Selector) {
        guard builder.system == .main, inMenuBar else { return }
        func group(_ shortcuts: [KeyboardShortcut]) -> UIMenu {
            UIMenu(options: .displayInline, children: shortcuts.map { $0.command(action: action) })
        }
        // New Window and Close Window are the system's where it already offers them.
        func offers(_ menu: UIMenu.Identifier) -> Bool { builder.menu(for: menu)?.children.isEmpty == false }
        builder.insertChild(group(offers(.newItem) ? [.newMessage] : [.newMessage, .newWindow]), atStartOfMenu: .file)
        if !offers(.close) { builder.insertChild(group([.closeWindow]), atEndOfMenu: .file) }

        if builder.menu(for: .preferences) != nil {
            builder.replaceChildren(ofMenu: .preferences) { _ in [KeyboardShortcut.settings.command(action: action)] }
        } else {
            builder.insertChild(group([.settings]), atEndOfMenu: .application)
        }

        let message = UIMenu(
            title: String(localized: "Message", table: "Keyboard", bundle: .module, comment: "Menu bar menu"),
            identifier: UIMenu.Identifier("com.idanbirman.goodmail.message"),
            children: [
                group([.reply, .replyAll, .forward]), group([.send]), group([.markUnread, .star]),
                group([.archive, .trash]), group([.previousThread, .nextThread]),
            ])
        // Search Mail's ⌥⌘F belongs to Edit > Find & Replace here, and UIKit drops a whole menu whose keys repeat one
        // already in the bar. So Search Mail carries no keys of its own: the window answers Find & Replace with it
        // while no text has the keyboard.
        let search = UICommand(
            title: KeyboardShortcut.search.title, action: action, propertyList: KeyboardShortcut.search.rawValue)
        let mailbox = UIMenu(
            title: String(localized: "Mailbox", table: "Keyboard", bundle: .module, comment: "Menu bar menu"),
            identifier: UIMenu.Identifier("com.idanbirman.goodmail.mailbox"),
            children: [group([.getMail]), UIMenu(options: .displayInline, children: [search])])
        // After View, as in Apple Mail, or after the last standard menu the bar has. Each goes in on its own, so one
        // the builder refuses can't take the other with it.
        let anchor = [UIMenu.Identifier.view, .format, .edit, .file].first { builder.menu(for: $0) != nil }
        for menu in [message, mailbox] {
            if let anchor {
                builder.insertSibling(menu, afterMenu: anchor)
            } else {
                builder.insertChild(menu, atEndOfMenu: .root)
            }
        }
    }
}
