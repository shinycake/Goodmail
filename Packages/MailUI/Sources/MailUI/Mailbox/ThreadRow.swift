import MailCore
import UIKit

/// A mailbox row: sender and time, the subject in semibold, then the preview. The account badge marks unread mail,
/// and in a view spanning accounts, which account the thread belongs to.
struct ThreadRowConfiguration: UIContentConfiguration, Equatable {
    var thread: ThreadSummary
    var dateText: String
    /// `nil` while the thread's account is gone, as while it is being removed.
    var account: RowAccount?
    var display = RowDisplay.standard

    func makeContentView() -> any UIView & UIContentView {
        ThreadRowContentView(configuration: self)
    }

    func updated(for state: any UIConfigurationState) -> ThreadRowConfiguration { self }
}

final class ThreadRowContentView: UIView, UIContentView {
    private var current: ThreadRowConfiguration
    private let avatar = MonogramView()
    private let sender = UILabel()
    private let date = UILabel()
    private let mutedMark = UIImageView(image: UIImage(systemName: "bell.slash.fill"))
    private let subject = UILabel()
    private let preview = UILabel()
    /// The sender, subject and preview, whose trailing end fades out under the quick actions.
    private let text = UIStackView()
    private let textFade = CAGradientLayer()

    /// What a press from VoiceOver or another assistive app does, where the list's clicks aren't the collection
    /// view's own selection; `nil` leaves the press to the collection view.
    var activate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let activate else { return super.accessibilityActivate() }
        activate()
        return true
    }

    /// The buttons that float over the row's trailing end, and tint it, while the pointer rests on it; `nil` shows the
    /// time. The time and the muted mark fade out under them and back in after.
    var quickActions: HoverActionsView? {
        didSet {
            guard quickActions !== oldValue else { return }
            backgroundColor = quickActions == nil ? nil : .tertiarySystemFill
            if let quickActions {
                quickActions.translatesAutoresizingMaskIntoConstraints = false
                addSubview(quickActions)
                NSLayoutConstraint.activate([
                    quickActions.trailingAnchor.constraint(
                        equalTo: trailingAnchor, constant: -ThreadRowMetrics.quickActionsInset),
                    quickActions.centerYAnchor.constraint(equalTo: centerYAnchor),
                ])
            }
            setNeedsLayout()  // fits the buttons and fades the text, or takes the fade away
            // One row's buttons swapping for another set shows at once; coming and going cross-fades.
            guard (oldValue == nil) != (quickActions == nil) else {
                oldValue?.removeFromSuperview()
                return
            }
            quickActions?.alpha = 0
            let trailing = [date, mutedMark]
            UIView.animate(withDuration: 0.15) { [quickActions] in
                quickActions?.alpha = 1
                oldValue?.alpha = 0
                for view in trailing { view.alpha = quickActions == nil ? 1 : 0 }
            } completion: { _ in
                oldValue?.removeFromSuperview()
            }
        }
    }

    override func layoutSubviews() {
        // The capsule fits its buttons to the room before the constraints place it.
        quickActions?.room = (bounds.width * ThreadRowMetrics.quickActionsShare).rounded(.down)
        super.layoutSubviews()
        fadeTextUnderQuickActions()
    }

    /// Fades the text out just before the capsule's leading edge, so letters don't run under it.
    private func fadeTextUnderQuickActions() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let quickActions, text.bounds.width > 0 else {
            text.layer.mask = nil
            return
        }
        let capsule = quickActions.convert(quickActions.bounds, to: text)
        let leftToRight = effectiveUserInterfaceLayoutDirection == .leftToRight
        // How far from the text's leading edge the fade ends, a little before the capsule.
        let clear = (leftToRight ? capsule.minX : text.bounds.width - capsule.maxX) - 4
        let width = text.bounds.width
        let end = min(max(clear / width, 0), 1)
        let start = min(max((clear - ThreadRowMetrics.textFadeLength) / width, 0), end)
        textFade.frame = text.bounds
        textFade.colors = [UIColor.black, .black, .clear, .clear].map(\.cgColor)
        textFade.locations = [0, start, end, 1].map { NSNumber(value: Double($0)) }
        textFade.startPoint = CGPoint(x: leftToRight ? 0 : 1, y: 0.5)
        textFade.endPoint = CGPoint(x: leftToRight ? 1 : 0, y: 0.5)
        text.layer.mask = textFade
    }

    var configuration: any UIContentConfiguration {
        get { current }
        set {
            guard let configuration = newValue as? ThreadRowConfiguration, configuration != current else { return }
            current = configuration
            apply()
        }
    }

    init(configuration: ThreadRowConfiguration) {
        current = configuration
        super.init(frame: .zero)
        build()
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// List cells ask with an unbounded target height, which outweighs the labels' hugging and yields an infinite
    /// row. Sizing against the smallest height instead gives the row its natural height.
    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontal: UILayoutPriority,
        verticalFittingPriority vertical: UILayoutPriority
    ) -> CGSize {
        super.systemLayoutSizeFitting(
            CGSize(width: targetSize.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: horizontal,
            verticalFittingPriority: vertical
        )
    }

    private func build() {
        for label in [sender, date, subject, preview] {
            label.adjustsFontForContentSizeCategory = true
        }
        sender.font = .preferredFont(forTextStyle: .body)
        date.font = .preferredFont(forTextStyle: .footnote)
        date.textColor = .secondaryLabel
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        date.setContentHuggingPriority(.required, for: .horizontal)
        subject.font = Typography.subject
        preview.font = .preferredFont(forTextStyle: .subheadline)
        preview.textColor = .secondaryLabel

        mutedMark.tintColor = .secondaryLabel
        mutedMark.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1)
        mutedMark.setContentHuggingPriority(.required, for: .horizontal)
        mutedMark.setContentCompressionResistancePriority(.required, for: .horizontal)
        let header = UIStackView(arrangedSubviews: [sender, mutedMark, date])
        header.spacing = 8
        header.stacksVerticallyAtAccessibilitySizes()
        for view in [header, subject, preview] { text.addArrangedSubview(view) }
        text.axis = .vertical
        text.spacing = 2

        for view in [avatar, text] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // Edge constraints rather than the layout-margins guide, which list cells rewrite while self-sizing.
        let insets = ThreadRowMetrics.insets
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.leading),
            avatar.topAnchor.constraint(equalTo: topAnchor, constant: insets.top + 2),
            avatar.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -insets.bottom),
            text.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: ThreadRowMetrics.avatarSpacing),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.trailing),
            text.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
        isAccessibilityElement = true
        // The labels' attributed text carries its font, which doesn't scale on its own; set it again at the new size.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: ThreadRowContentView, _) in
            view.apply()
        }
    }

    private func apply() {
        let thread = current.thread
        let name = thread.sender.displayName
        sender.font = .preferredFont(forTextStyle: .body).withWeight(thread.isUnread ? .semibold : .regular)
        sender.setContentText(name, alignedToContent: false)
        date.text = current.dateText
        let isMuted = thread.labelIDs.contains(SystemLabel.muted)
        mutedMark.isHidden = !isMuted
        let subjectText = thread.subject.isEmpty ? ThreadRowMetrics.noSubject : thread.subject
        subject.setSubjectText(subjectText)
        preview.setContentText(thread.snippet)
        preview.numberOfLines = current.display.previewLines
        preview.isHidden = current.display.previewLines == 0 || thread.snippet.isEmpty
        avatar.configure(
            name: name, address: thread.sender.address, badge: current.account?.badge(unread: thread.isUnread),
            showingMonogram: current.display.showsAvatars)

        accessibilityLabel = [
            thread.isUnread
                ? String(localized: "Unread", table: "Mailbox", bundle: .module, comment: "VoiceOver: thread state")
                : nil,
            isMuted
                ? String(localized: "Muted", table: "Mailbox", bundle: .module, comment: "VoiceOver: thread state")
                : nil,
            current.account?.spokenAccount, name, subjectText, current.dateText,
            preview.isHidden ? nil : thread.snippet,
        ].compactMap(\.self).joined(separator: ", ")
        // Voice Control names the row by what it shows first, not by the whole spoken label.
        accessibilityUserInputLabels = [name, subjectText]
    }
}

extension RowAccount {
    func badge(unread: Bool) -> MonogramView.Badge? {
        switch self {
        case .implied(let color): unread ? .dot(color.uiColor) : nil
        case .shown(let color, _): unread ? .dot(color.uiColor) : .ring(color.uiColor)
        }
    }

    /// The account VoiceOver names, where the color alone says it.
    var spokenAccount: String? {
        guard case .shown(_, let name) = self else { return nil }
        return name
    }
}

enum ThreadRowMetrics {
    static let insets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    static let avatarSpacing: CGFloat = 12
    /// Between the quick actions and the row's trailing edge.
    static let quickActionsInset: CGFloat = 11
    /// The most of the row's width the quick actions take.
    static let quickActionsShare: CGFloat = 0.6
    /// How long the text's fade is before the quick actions.
    static let textFadeLength: CGFloat = 24
    /// Where separators start, so they line up with the text rather than the avatar.
    static func textLeadingInset(for display: RowDisplay) -> CGFloat {
        insets.leading + MonogramView.width(showingMonogram: display.showsAvatars) + avatarSpacing
    }
    static var noSubject: String {
        String(
            localized: "(No Subject)", table: "Mailbox", bundle: .module,
            comment: "Shown in place of an empty email subject")
    }
}

extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
