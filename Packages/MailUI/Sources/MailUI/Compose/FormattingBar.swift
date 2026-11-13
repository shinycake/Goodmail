import UIKit

/// The formatting controls above the keyboard while the body is being written: the four styles, lists, quote, link
/// and the paragraph's direction. Each shows whether the selection has it. The system's Format menu and panel, on a
/// selection, offer the styles and lists too.
final class FormattingBar: UIToolbar {
    /// A control was used. `.link` asks for an address first, so it comes through `onLink`.
    var onCommand: (FormattingCommand) -> Void = { _ in }
    var onLink: () -> Void = {}
    private var styleItems: [(RichText.Style, UIBarButtonItem)] = []
    private let listItem = UIBarButtonItem()
    private let quoteItem = UIBarButtonItem()
    private let linkItem = UIBarButtonItem()
    private let directionItem = UIBarButtonItem()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: 44))
        styleItems = RichText.Style.allCases.map { style in
            let item = UIBarButtonItem(
                title: style.title, image: UIImage(systemName: style.symbol),
                primaryAction: UIAction { [weak self] _ in self?.onCommand(.toggle(style)) })
            item.accessibilityLabel = style.title
            return (style, item)
        }
        listItem.image = UIImage(systemName: "list.bullet")
        listItem.accessibilityLabel = String(localized: "List", bundle: .module, comment: "Formatting: the list menu")
        quoteItem.primaryAction = UIAction(
            title: String(localized: "Quote", bundle: .module, comment: "Formatting: quotes the paragraph"),
            image: UIImage(systemName: "text.quote")
        ) { [weak self] _ in self?.onCommand(.block(.quote)) }
        linkItem.primaryAction = UIAction(
            title: String(localized: "Link", bundle: .module, comment: "Formatting: links the selection"),
            image: UIImage(systemName: "link")
        ) { [weak self] _ in self?.onLink() }
        directionItem.image = UIImage(systemName: "arrow.left.arrow.right")
        directionItem.accessibilityLabel = String(
            localized: "Text Direction", bundle: .module, comment: "Formatting: the paragraph direction menu")
        let controls = styleItems.map(\.1) + [listItem, quoteItem, linkItem, directionItem]
        items = controls.flatMap { [$0, .flexibleSpace()] }.dropLast()
        show(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Shows which controls are on for `formatting`; `nil` shows them all off.
    func show(_ formatting: Formatting?) {
        for (style, item) in styleItems { item.isSelected = formatting?.styles.contains(style) ?? false }
        let block = formatting?.block ?? .body
        listItem.isSelected = block == .bulleted || block == .numbered
        listItem.menu = UIMenu(
            children: [
                (
                    RichText.Block.bulleted, "list.bullet",
                    String(localized: "Bulleted List", bundle: .module, comment: "Formatting: a bulleted list")
                ),
                (
                    .numbered, "list.number",
                    String(localized: "Numbered List", bundle: .module, comment: "Formatting: a numbered list")
                ),
            ].map { list, symbol, title in
                UIAction(title: title, image: UIImage(systemName: symbol), state: block == list ? .on : .off) {
                    [weak self] _ in self?.onCommand(.block(list))
                }
            })
        quoteItem.isSelected = block == .quote
        linkItem.isSelected = formatting?.link != nil
        let direction = formatting?.direction ?? .auto
        directionItem.menu = UIMenu(
            title: String(
                localized: "Text Direction", bundle: .module, comment: "Formatting: the paragraph direction menu"),
            options: .singleSelection,
            children: RichText.Direction.allCases.map { choice in
                UIAction(title: choice.title, state: choice == direction ? .on : .off) { [weak self] _ in
                    self?.onCommand(.direction(choice))
                }
            })
    }
}

extension RichText.Style {
    fileprivate var title: String {
        switch self {
        case .bold: String(localized: "Bold", bundle: .module, comment: "Formatting: bold text")
        case .italic: String(localized: "Italic", bundle: .module, comment: "Formatting: italic text")
        case .underline: String(localized: "Underline", bundle: .module, comment: "Formatting: underlined text")
        case .strikethrough:
            String(localized: "Strikethrough", bundle: .module, comment: "Formatting: struck-through text")
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        }
    }
}

extension RichText.Direction {
    fileprivate var title: String {
        switch self {
        case .auto:
            String(localized: "Automatic", bundle: .module, comment: "Text direction: follows what is typed")
        case .leftToRight: String(localized: "Left to Right", bundle: .module, comment: "Text direction")
        case .rightToLeft: String(localized: "Right to Left", bundle: .module, comment: "Text direction")
        }
    }
}
