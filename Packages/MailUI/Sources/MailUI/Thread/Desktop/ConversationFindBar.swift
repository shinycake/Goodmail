import UIKit

/// The find bar under the reader's top bar: a field, what the last search found, Previous and Next, and Done. It
/// shows `ConversationFind.State` and tells what the reader typed and pressed.
final class ConversationFindBar: UIView {
    var onQuery: ((String) -> Void)?
    var onStep: ((_ backwards: Bool) -> Void)?
    var onDone: (() -> Void)?

    private let field = UISearchTextField()
    private let status = UILabel()
    private let previous = UIButton(configuration: .plain())
    private let nextMatch = UIButton(configuration: .plain())

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        let glass = UIVisualEffectView(effect: UIGlassEffect())
        glass.cornerConfiguration = .capsule()
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        field.placeholder = String(
            localized: "Find in Conversation", table: "Thread", bundle: .module,
            comment: "Placeholder of the find bar's field")
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.addAction(UIAction { [weak self] _ in self?.onQuery?(self?.field.text ?? "") }, for: .editingChanged)
        field.addAction(UIAction { [weak self] _ in self?.onStep?(false) }, for: .primaryActionTriggered)
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = .secondaryLabel
        status.adjustsFontForContentSizeCategory = true
        status.setContentHuggingPriority(.required, for: .horizontal)
        status.setContentCompressionResistancePriority(.required, for: .horizontal)
        configure(
            previous, symbol: "chevron.up", backwards: true,
            title: String(
                localized: "Previous Match", table: "Thread", bundle: .module,
                comment: "Find bar button, with its key ⇧⌘G in the tooltip"))
        configure(
            nextMatch, symbol: "chevron.down", backwards: false,
            title: String(
                localized: "Next Match", table: "Thread", bundle: .module,
                comment: "Find bar button, with its key ⌘G in the tooltip"))
        let done = UIButton(
            configuration: .plain(),
            primaryAction: UIAction(
                title: String(localized: "Done", table: "Thread", bundle: .module, comment: "Closes the find bar")
            ) { [weak self] _ in self?.onDone?() })
        done.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [field, status, previous, nextMatch, done])
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    private func configure(_ button: UIButton, symbol: String, backwards: Bool, title: String) {
        button.configuration?.image = UIImage(systemName: symbol)
        button.accessibilityLabel = title
        button.toolTip = title
        button.addAction(UIAction { [weak self] _ in self?.onStep?(backwards) }, for: .primaryActionTriggered)
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    /// Escape closes the bar from the field.
    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(done))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }

    @objc private func done() {
        onDone?()
    }

    func show(_ state: ConversationFind.State) {
        switch state {
        case .closed:
            isHidden = true
            field.text = nil
            _ = field.resignFirstResponder()
        case .open(_, let outcome):
            isHidden = false
            status.text =
                outcome == .notFound
                ? String(
                    localized: "Not Found", table: "Thread", bundle: .module,
                    comment: "Find bar: the words aren't in any open letter")
                : nil
        }
        let canStep = state != .closed && field.text?.isEmpty == false
        previous.isEnabled = canStep
        nextMatch.isEnabled = canStep
    }

    /// Puts the cursor in the field with its words selected, for Find when the bar already shows.
    func focus() {
        _ = field.becomeFirstResponder()
        field.selectAll(nil)
    }
}
