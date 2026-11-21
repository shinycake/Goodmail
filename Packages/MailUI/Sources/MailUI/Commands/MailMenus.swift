import MailCore
public import UIKit

/// The app's commands in the iPadOS and Mac menu bar, which also lists them while Command is held. Each goes in the
/// section `MailCommand.place` names: into the system's own File, Edit, View and Format menus, and into Mailbox and
/// Message menus as in Apple Mail. Every command performs through `action` on the window, which enables only what the
/// screens on show answer (`CommandRouting`) and titles and checks each item as they say.
@MainActor
public enum MailMenus {
    /// Whether the menu bar carries the commands, as on iPad and the Mac. Elsewhere the window offers them as key
    /// commands of its own, so a keyboard reaches them on iPhone too. A fact about the device, so it reads the idiom
    /// through `InteractionStyle.showsMenuBar`.
    public static var inMenuBar: Bool { InteractionStyle.showsMenuBar(idiom: UIDevice.current.userInterfaceIdiom) }

    public static func build(_ builder: any UIMenuBuilder, action: Selector) {
        guard builder.system == .main, inMenuBar else { return }
        keepMailFileItems(builder)
        if builder.menu(for: .font) != nil {
            builder.replaceChildren(ofMenu: .font, from: withoutSizeKeys)
        }
        func offers(_ menu: UIMenu.Identifier) -> Bool { builder.menu(for: menu)?.children.isEmpty == false }

        /// The command's item, or `nil` where the system's own item does all of it.
        func item(for command: MailCommand) -> UICommand? {
            switch command.keys {
            case .none: return command.menuItem(nil, action: action)
            case .own(let chord): return command.menuItem(chord, action: action)
            case .system(let item):
                guard offers(item.menu) else { return command.menuItem(item.keys, action: action) }
                return item.keepsCommandItem ? command.menuItem(nil, action: action) : nil
            }
        }
        let sections: [(place: MenuPlace, menu: UIMenu)] = MenuPlace.allCases.compactMap { place in
            let items = MailCommand.allCases.filter { $0.place == place }.compactMap(item(for:))
            guard !items.isEmpty else { return nil }
            // A submenu shows under its own title; any other section sits between lines.
            return (
                place,
                place.submenu.map { UIMenu(title: $0.title, children: items) }
                    ?? UIMenu(options: .displayInline, children: items)
            )
        }

        // Settings takes the place of the system's own item, which would open the app's page in the Settings app.
        if let settings = sections.first(where: { $0.place == .settings })?.menu {
            if builder.menu(for: .preferences) != nil {
                builder.replaceChildren(ofMenu: .preferences) { _ in settings.children }
            } else {
                builder.insertChild(settings, atEndOfMenu: .application)
            }
        }

        // Each section goes in on its own, so one the builder refuses can't take the others with it.
        var added: [UIMenu] = []
        for menu in [MenuBarMenu.file, .edit, .view, .mailbox, .message, .format] {
            let mine = sections.filter { $0.place.menu == menu }
            guard !mine.isEmpty else { continue }
            guard let system = menu.systemMenu, builder.menu(for: system) != nil else {
                added.append(
                    UIMenu(
                        title: menu.title, identifier: UIMenu.Identifier("com.idanbirman.goodmail.\(menu)"),
                        children: mine.map(\.menu)))
                continue
            }
            for section in mine {
                if section.place == .fileNew {
                    builder.insertChild(section.menu, atStartOfMenu: system)
                } else {
                    builder.insertChild(section.menu, atEndOfMenu: system)
                }
            }
        }
        // The app's own menus go after View, as in Apple Mail, or after the last standard menu the bar has, in order.
        guard
            let anchor = [UIMenu.Identifier.view, .format, .edit, .file].first(where: { builder.menu(for: $0) != nil })
        else {
            for menu in added { builder.insertChild(menu, atEndOfMenu: .root) }
            return
        }
        for menu in added.reversed() { builder.insertSibling(menu, afterMenu: anchor) }
    }
}

extension MenuBarMenu {
    /// The system's menu of this name, or `nil` for the menus the app adds itself.
    fileprivate var systemMenu: UIMenu.Identifier? {
        switch self {
        case .application: .application
        case .file: .file
        case .edit: .edit
        case .view: .view
        case .format: .format
        case .mailbox, .message: nil
        }
    }
}
