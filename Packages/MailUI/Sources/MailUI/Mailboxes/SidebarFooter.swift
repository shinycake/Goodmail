public import MailCore
import UIKit

/// Where a desktop sidebar's footer learns how mail is coming in, and how it fixes an account's problem.
public struct SyncFooterSource {
    let health: AccountHealthBoard
    let accounts: [Account]
    let fix: (AccountProblemNotice) async -> Void

    public init(
        health: AccountHealthBoard, accounts: [Account], fix: @escaping (AccountProblemNotice) async -> Void
    ) {
        self.health = health
        self.accounts = accounts
        self.fix = fix
    }

    var status: SyncStatus { SyncStatus(health, accounts: accounts) }
}

/// The quiet line under a desktop sidebar: how mail is coming in, and New Label at its end. A problem's line is a
/// button that asks about it, with its fix.
final class SidebarFooterView: UIView {
    private let line = ConfiguredButton(configuration: .plain())
    private let newLabel: UIButton?
    var onProblem: ((AccountProblemNotice) -> Void)?
    private var shown = SyncStatus.quiet

    init(newLabel item: UIBarButtonItem?) {
        newLabel = item.map { item in
            var configuration = UIButton.Configuration.plain()
            configuration.image = item.image
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .subheadline)
            let button = ConfiguredButton(configuration: configuration, primaryAction: item.primaryAction)
            button.menu = item.menu
            button.showsMenuAsPrimaryAction = item.menu != nil
            button.toolTip = item.title
            button.accessibilityLabel = item.title
            return button
        }
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
        line.configuration = configuration
        line.contentHorizontalAlignment = .leading
        line.addAction(
            UIAction { [weak self] _ in
                guard let self, case .problem(let notice) = shown else { return }
                onProblem?(notice)
            }, for: .primaryActionTriggered)
        line.accessibilityIdentifier = "sidebar.syncStatus"
        let row = UIStackView(arrangedSubviews: [line] + [newLabel].compactMap(\.self))
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func show(_ status: SyncStatus, now: Date = .now) {
        shown = status
        let problem: Bool
        if case .problem = status { problem = true } else { problem = false }
        var title = AttributedString(status.text(now: now) ?? "")
        title.font = UIFont.preferredFont(forTextStyle: .footnote)
        title.foregroundColor = problem ? UIColor.systemOrange : UIColor.secondaryLabel
        line.configuration?.attributedTitle = title
        line.configuration?.image = problem ? UIImage(systemName: "exclamationmark.triangle.fill") : nil
        line.configuration?.imagePadding = 4
        line.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .footnote)
        line.configuration?.baseForegroundColor = problem ? .systemOrange : .secondaryLabel
        line.isUserInteractionEnabled = problem
        line.accessibilityTraits = problem ? .button : .staticText
    }
}
