import UIKit

extension MailMenus {
    /// Format > Font's Bigger and Smaller without their keys, which Zoom In and Zoom Out take, as in Apple Mail. The
    /// composer answers those by growing or shrinking its text, so the keys still size it while it's writing. UIKit
    /// drops a whole menu whose item repeats keys another holds, so both can't have them.
    static func withoutSizeKeys(_ items: [UIMenuElement]) -> [UIMenuElement] {
        let sizes = [#selector(UIResponder.increaseSize(_:)), #selector(UIResponder.decreaseSize(_:))]
        return items.map { item in
            switch item {
            case let menu as UIMenu:
                return menu.replacingChildren(withoutSizeKeys(menu.children))
            case let key as UIKeyCommand:
                guard let action = key.action, sizes.contains(action) else { return key }
                let command = UICommand(
                    title: key.title, image: key.image, action: action, propertyList: key.propertyList,
                    attributes: key.attributes, state: key.state)
                command.discoverabilityTitle = key.discoverabilityTitle
                return command
            default:
                return item
            }
        }
    }
}
