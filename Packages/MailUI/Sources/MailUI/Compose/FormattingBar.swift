import UIKit

/// The formatting controls above the keyboard while the body is being written: the four styles, size, color, lists,
/// quote, link and the paragraph's direction, side by side in one glass capsule that scrolls sideways when they don't
/// all fit. Each shows whether the selection has it. The system's Format menu and panel, on a selection, offer the
/// styles and lists too.
final class FormattingBar: UIView {
    /// A control was used. `.link` asks for an address first, so it comes through `onLink`.
    var onCommand: (FormattingCommand) -> Void = { _ in }
    var onLink: () -> Void = {}
    private var styleButtons: [(RichText.Style, UIButton)] = []
    private let sizeButton: UIButton
    private let colorButton: UIButton
    private let listButton: UIButton
    private let quoteButton: UIButton
    private let linkButton: UIButton
    private let directionButton: UIButton
    private let scrollView = UIScrollView()
    private let fade = CAGradientLayer()
    /// Arrows at the edges that have more controls past them: they show the bar scrolls, and a tap scrolls it.
    private let moreLeft = FormattingBar.moreButton(symbol: "chevron.compact.left")
    private let moreRight = FormattingBar.moreButton(symbol: "chevron.compact.right")
    /// The width the controls were last placed for; at a new width they go back to their start.
    private var laidOutWidth: CGFloat = 0

    /// The capsule's height; the controls sit inside it with room around their highlight.
    private static let capsuleHeight: CGFloat = 52
    private static let inset: CGFloat = 8
    private static let buttonSize = CGSize(width: 44, height: 40)
    /// How far the controls fade out at an edge that has more of them past it.
    private static let fadeLength: CGFloat = 36
    /// The width of the arrows at the edges, over the fade.
    private static let moreWidth: CGFloat = 22

    init() {
        sizeButton = Self.button(
            symbol: "textformat.size",
            title: String(
                localized: "Text Size", table: "Formatting", bundle: .module, comment: "Formatting: the text size menu")
        )
        colorButton = Self.button(
            symbol: "paintpalette",
            title: String(
                localized: "Text Color", table: "Formatting", bundle: .module,
                comment: "Formatting: the text color menu"))
        listButton = Self.button(
            symbol: "list.bullet",
            title: String(localized: "List", table: "Compose", bundle: .module, comment: "Formatting: the list menu"))
        quoteButton = Self.button(
            symbol: "text.quote",
            title: String(
                localized: "Quote", table: "Compose", bundle: .module, comment: "Formatting: quotes the paragraph"))
        linkButton = Self.button(
            symbol: "link",
            title: String(
                localized: "Link", table: "Compose", bundle: .module, comment: "Formatting: links the selection"))
        directionButton = Self.button(
            symbol: "arrow.left.arrow.right",
            title: String(
                localized: "Text Direction", table: "Compose", bundle: .module,
                comment: "Formatting: the paragraph direction menu"))
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: Self.capsuleHeight + Self.inset))
        // Flexible height lets the system grow the bar by the bottom safe area when it sits at the screen's edge,
        // as it does with a hardware keyboard, so the capsule clears the home indicator and the rounded corners. The
        // capsule hangs from the top and leaves that growth empty: tying it to the safe area as well made each height
        // the system tried ask for another, and on iPad the keyboard then swapped between the software keyboard and
        // the hardware keyboard's bar without end.
        autoresizingMask = .flexibleHeight
        // At the largest text sizes, pressing and holding a control shows its name large.
        addInteraction(UILargeContentViewerInteraction())
        styleButtons = RichText.Style.allCases.map { style in
            let button = Self.button(symbol: style.symbol, title: style.title)
            button.addAction(
                UIAction { [weak self] _ in self?.onCommand(.toggle(style)) }, for: .primaryActionTriggered)
            return (style, button)
        }
        quoteButton.addAction(
            UIAction { [weak self] _ in self?.onCommand(.quote(.toggle)) }, for: .primaryActionTriggered)
        linkButton.addAction(UIAction { [weak self] _ in self?.onLink() }, for: .primaryActionTriggered)
        for button in [sizeButton, colorButton, listButton, directionButton] { button.showsMenuAsPrimaryAction = true }

        let glass = UIVisualEffectView(effect: UIGlassEffect())
        glass.cornerConfiguration = .capsule()
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(scrollView)
        let controls = UIStackView(
            arrangedSubviews: styleButtons.map(\.1) + [
                sizeButton, colorButton, listButton, quoteButton, linkButton, directionButton,
            ])
        controls.spacing = 4
        controls.alignment = .center
        controls.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(controls)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        scrollView.layer.mask = fade
        for more in [moreLeft, moreRight] {
            more.translatesAutoresizingMaskIntoConstraints = false
            glass.contentView.addSubview(more)
        }
        moreLeft.addAction(
            UIAction { [weak self] _ in self?.scrollPage(towardRight: false) }, for: .primaryActionTriggered)
        moreRight.addAction(
            UIAction { [weak self] _ in self?.scrollPage(towardRight: true) }, for: .primaryActionTriggered)

        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset / 2),
            glass.heightAnchor.constraint(equalToConstant: Self.capsuleHeight),
            glass.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Self.inset),
            glass.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Self.inset),
            scrollView.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: Self.inset),
            scrollView.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -Self.inset),
            controls.topAnchor.constraint(equalTo: content.topAnchor),
            controls.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            controls.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            // When everything fits, the controls spread across the capsule; otherwise they keep their size and scroll.
            controls.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
            moreLeft.leftAnchor.constraint(equalTo: glass.contentView.leftAnchor, constant: 2),
            moreRight.rightAnchor.constraint(equalTo: glass.contentView.rightAnchor, constant: -2),
        ])
        for more in [moreLeft, moreRight] {
            NSLayoutConstraint.activate([
                more.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
                more.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
                more.widthAnchor.constraint(equalToConstant: Self.moreWidth),
            ])
        }
        controls.distribution = .equalSpacing
        show(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.capsuleHeight + Self.inset)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Right to left, the controls start at the right: show that end first, as a left-to-right bar shows its left.
        if bounds.width != laidOutWidth {
            laidOutWidth = bounds.width
            scrollView.layoutIfNeeded()
            let start =
                effectiveUserInterfaceLayoutDirection == .rightToLeft
                ? max(scrollView.contentSize.width - scrollView.bounds.width, 0) : 0
            scrollView.contentOffset.x = start
        }
        updateFade()
    }

    /// Fades the controls out at each edge that has more of them past it, so the bar reads as one that scrolls.
    private func updateFade() {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let offset = scrollView.contentOffset.x
        let hiddenBefore = offset > 1
        let hiddenAfter = offset + width < scrollView.contentSize.width - 1
        // Under an arrow the controls are gone, so the arrow never sits on half of one; past it they fade in.
        let under = (Self.moreWidth + 2 - Self.inset) / width
        let edge = Self.fadeLength / width
        let opaque = UIColor.black.cgColor
        let clear = UIColor.clear.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = scrollView.bounds
        let before = hiddenBefore ? clear : opaque
        let after = hiddenAfter ? clear : opaque
        fade.colors = [before, before, opaque, opaque, after, after]
        fade.locations = [0, under, edge, 1 - edge, 1 - under, 1].map { NSNumber(value: $0) }
        CATransaction.commit()
        moreLeft.isHidden = !hiddenBefore
        moreRight.isHidden = !hiddenAfter
    }

    /// Scrolls the controls a page toward the right or left, keeping the edge's fade's worth of the last page.
    private func scrollPage(towardRight: Bool) {
        let page = max(scrollView.bounds.width - 2 * Self.fadeLength, Self.buttonSize.width)
        let maxOffset = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        let target = scrollView.contentOffset.x + (towardRight ? page : -page)
        scrollView.setContentOffset(CGPoint(x: min(max(target, 0), maxOffset), y: 0), animated: true)
    }

    /// An arrow at an edge with more controls past it. VoiceOver reaches every control by scrolling already, so it
    /// skips the arrows.
    private static func moreButton(symbol: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            textStyle: .body, scale: .large)
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.isHidden = true
        button.isAccessibilityElement = false
        return button
    }

    private static func button(symbol: String, title: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = title
        button.largeContentTitle = title
        button.showsLargeContentViewer = true
        // A control that is on fills in, as the system's own formatting toggles do.
        button.configurationUpdateHandler = { button in
            var configuration = button.configuration
            configuration?.background.backgroundColor = button.isSelected ? .tertiarySystemFill : .clear
            button.configuration = configuration
        }
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize.width),
            button.heightAnchor.constraint(equalToConstant: buttonSize.height),
        ])
        return button
    }

    /// Shows which controls are on for `formatting`; `nil` shows them all off.
    func show(_ formatting: Formatting?) {
        for (style, button) in styleButtons { button.isSelected = formatting?.styles.contains(style) ?? false }
        sizeButton.menu = UIMenu(
            title: String(
                localized: "Text Size", table: "Formatting", bundle: .module, comment: "Formatting: the text size menu"),
            options: .singleSelection,
            children: RichText.Size.allCases.reversed().map { size in
                UIAction(title: size.title, state: formatting?.size == size ? .on : .off) { [weak self] _ in
                    self?.onCommand(.size(size))
                }
            })
        colorButton.menu = UIMenu(
            title: String(
                localized: "Text Color", table: "Formatting", bundle: .module,
                comment: "Formatting: the text color menu"),
            options: .singleSelection,
            children: RichText.TextColor.allCases.map { color in
                UIAction(
                    title: color.title,
                    image: UIImage(systemName: "circle.fill")?.withTintColor(
                        color.color, renderingMode: .alwaysOriginal),
                    state: formatting?.color == color ? .on : .off
                ) { [weak self] _ in self?.onCommand(.color(color)) }
            })
        let block = formatting?.block ?? .body
        listButton.isSelected = block == .bulleted || block == .numbered
        listButton.menu = UIMenu(
            children: [
                (
                    RichText.Block.bulleted, "list.bullet",
                    String(
                        localized: "Bulleted List", table: "Compose", bundle: .module,
                        comment: "Formatting: a bulleted list")
                ),
                (
                    .numbered, "list.number",
                    String(
                        localized: "Numbered List", table: "Compose", bundle: .module,
                        comment: "Formatting: a numbered list")
                ),
            ].map { list, symbol, title in
                UIAction(title: title, image: UIImage(systemName: symbol), state: block == list ? .on : .off) {
                    [weak self] _ in self?.onCommand(.block(list))
                }
            })
        let quoteLevel = formatting?.quoteLevel ?? .none
        quoteButton.isSelected = quoteLevel.isQuoted
        // Pressing and holding the quote control nests it, as Mail's Quote Level does.
        quoteButton.menu = UIMenu(children: [
            UIAction(
                title: String(
                    localized: "Increase Quote Level", table: "Formatting", bundle: .module,
                    comment: "Formatting: quotes the paragraph one level deeper"),
                image: UIImage(systemName: "increase.quotelevel"),
                attributes: quoteLevel < .deepest ? [] : .disabled
            ) { [weak self] _ in self?.onCommand(.quote(.increase)) },
            UIAction(
                title: String(
                    localized: "Decrease Quote Level", table: "Formatting", bundle: .module,
                    comment: "Formatting: takes the paragraph out of its innermost quote"),
                image: UIImage(systemName: "decrease.quotelevel"),
                attributes: quoteLevel.isQuoted ? [] : .disabled
            ) { [weak self] _ in self?.onCommand(.quote(.decrease)) },
        ])
        linkButton.isSelected = formatting?.link != nil
        let direction = formatting?.direction ?? .auto
        directionButton.menu = UIMenu(
            title: String(
                localized: "Text Direction", table: "Compose", bundle: .module,
                comment: "Formatting: the paragraph direction menu"),
            options: .singleSelection,
            children: RichText.Direction.allCases.map { choice in
                UIAction(title: choice.title, state: choice == direction ? .on : .off) { [weak self] _ in
                    self?.onCommand(.direction(choice))
                }
            })
    }
}

extension FormattingBar: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateFade() }
}

extension RichText.Style {
    fileprivate var title: String {
        switch self {
        case .bold: String(localized: "Bold", table: "Compose", bundle: .module, comment: "Formatting: bold text")
        case .italic: String(localized: "Italic", table: "Compose", bundle: .module, comment: "Formatting: italic text")
        case .underline:
            String(localized: "Underline", table: "Compose", bundle: .module, comment: "Formatting: underlined text")
        case .strikethrough:
            String(
                localized: "Strikethrough", table: "Compose", bundle: .module,
                comment: "Formatting: struck-through text")
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

extension RichText.Size {
    fileprivate var title: String {
        switch self {
        case .small: String(localized: "Small", table: "Formatting", bundle: .module, comment: "Text size")
        case .normal: String(localized: "Normal", table: "Formatting", bundle: .module, comment: "Text size")
        case .large: String(localized: "Large", table: "Formatting", bundle: .module, comment: "Text size")
        case .huge: String(localized: "Huge", table: "Formatting", bundle: .module, comment: "Text size")
        }
    }
}

extension RichText.TextColor {
    fileprivate var title: String {
        switch self {
        case .automatic:
            String(
                localized: "Default Color", table: "Formatting", bundle: .module,
                comment: "Text color: the reader's own, black or white")
        case .red: String(localized: "Red", table: "Formatting", bundle: .module, comment: "Text color")
        case .orange: String(localized: "Orange", table: "Formatting", bundle: .module, comment: "Text color")
        case .green: String(localized: "Green", table: "Formatting", bundle: .module, comment: "Text color")
        case .blue: String(localized: "Blue", table: "Formatting", bundle: .module, comment: "Text color")
        case .purple: String(localized: "Purple", table: "Formatting", bundle: .module, comment: "Text color")
        case .gray: String(localized: "Gray", table: "Formatting", bundle: .module, comment: "Text color")
        }
    }
}

extension RichText.Direction {
    fileprivate var title: String {
        switch self {
        case .auto:
            String(
                localized: "Automatic", table: "Compose", bundle: .module,
                comment: "Text direction: follows what is typed")
        case .leftToRight:
            String(localized: "Left to Right", table: "Compose", bundle: .module, comment: "Text direction")
        case .rightToLeft:
            String(localized: "Right to Left", table: "Compose", bundle: .module, comment: "Text direction")
        }
    }
}
