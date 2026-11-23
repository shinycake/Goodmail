import MailCore
import UIKit

/// The filter button in the list's top bar. While the filter is on the button is filled, in the account's color the
/// bar wears.
@MainActor
final class FilterButton {
    /// How the button looks. Either way a tap or click opens the choices, as one glyph's pull-down.
    enum Look {
        /// A touch screen's bar: the circled glyph, filled and prominent while the filter is on.
        case touch
        /// A desktop toolbar's plain glyph, which only fills while the filter is on.
        case desktop
    }

    let item = UIBarButtonItem()
    /// How the button looks. A desktop window's list sets `.desktop`.
    var look = Look.touch {
        didSet { if look != oldValue { apply() } }
    }
    private var filter = ListFilter.none
    private let change: (ListFilter) -> Void

    /// `change` is told the filter the reader's choice makes.
    init(change: @escaping (ListFilter) -> Void) {
        self.change = change
        item.title = String(localized: "Filter", table: "Mailbox", bundle: .module, comment: "Button: filters the list")
        item.accessibilityIdentifier = "listFilter"
        apply()
    }

    /// Shows the filter the list has now, filled while it is on.
    func show(_ new: ListFilter) {
        guard new != filter else { return }
        filter = new
        apply()
    }

    private func apply() {
        switch look {
        case .touch:
            item.image = UIImage(
                systemName: filter.isOn
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            item.style = filter.isOn ? .prominent : .plain
        case .desktop:
            // A desktop toolbar shows plain glyphs: while the filter is on, the glyph fills and takes the tint.
            item.image = UIImage(
                systemName: filter.isOn
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
            item.style = .plain
        }
        item.accessibilityValue = filter.summary
        // With no primary action, the menu opens on a tap rather than a long press.
        item.menu = menu
    }

    /// Each choice, checked while the filter asks for it, and Turn Off Filter while it is on.
    private var menu: UIMenu {
        let choices = ListFilter.Option.allCases.map { option in
            UIAction(
                title: option.title, image: UIImage(systemName: option.symbol),
                state: filter.asks(for: option) ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                self.change(filter.toggling(option))
            }
        }
        var sections = [UIMenu(options: .displayInline, children: choices)]
        if filter.isOn {
            sections.append(
                UIMenu(
                    options: .displayInline,
                    children: [
                        UIAction(
                            title: Self.turnOffTitle, image: UIImage(systemName: "xmark.circle")
                        ) { [weak self] _ in
                            guard let self else { return }
                            self.change(filter.toggled())
                        }
                    ]))
        }
        return UIMenu(children: sections)
    }

    static let turnOffTitle = String(
        localized: "Turn Off Filter", table: "Mailbox", bundle: .module, comment: "Button: stops filtering the list")
    /// The View menu's item, which says what it does now.
    static let turnOffMenuTitle = String(
        localized: "Turn Filter Off", table: "Keyboard", bundle: .module, comment: "Menu bar command")
    static let turnOnMenuTitle = String(
        localized: "Turn Filter On", table: "Keyboard", bundle: .module, comment: "Menu bar command")
}
