import UIKit

extension MailMenus {
    /// On the Mac, File keeps of the system's own items only Close and Print, as Apple Mail's File menu does. The
    /// system's New Window holds ⌘N there, Mail's New Message, so it goes, and the app's New Viewer Window takes its
    /// place on ⌥⌘N, as in Mail. Duplicate, Move, Rename and Export As are for documents, and Close All for apps whose
    /// windows hold documents; a mail window is neither. iPad keeps its File menu as it is.
    static func keepMailFileItems(_ builder: any UIMenuBuilder) {
        guard InteractionStyle(idiom: UIDevice.current.userInterfaceIdiom) == .desktop else { return }
        for menu in [UIMenu.Identifier.newItem, .document] where builder.menu(for: menu) != nil {
            builder.remove(menu: menu)
        }
        // Close stays the system's, which closes the window the way its close button does. Should the system's item
        // answer some other action, it goes too, and Close Window takes ⌘W itself (`MailMenus.build`).
        guard builder.menu(for: .close) != nil else { return }
        builder.replaceChildren(ofMenu: .close) { items in
            items.filter { ($0 as? UICommand)?.action == #selector(UIResponder.performClose(_:)) }
        }
    }
}
