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

    /// What a press from VoiceOver or another assistive app does, where the list's clicks aren't the collection
    /// view's own selection; `nil` leaves the press to the collection view.
    var activate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let activate else { return super.accessibilityActivate() }
        activate()
        return true
    }

    /// Widens the time's place to the quick actions' width while they show.
    private var timeSlot: NSLayoutConstraint?

    /// The buttons that take the time's place in the row's upper trailing corner, and tint the row, while the pointer
    /// rests on it; `nil` shows the time. The time and the muted mark fade out under them and back in after.
    var quickActions: HoverActionsView? {
        didSet {
            guard quickActions !== oldValue else { return }
            backgroundColor = quickActions == nil ? nil : .tertiarySystemFill
            timeSlot?.isActive = false
            timeSlot = nil
            if let quickActions {
                // Placed by hand in layoutSubviews, over the row: constraints tying it to the time could stretch the
                // time's line to its height, and push the subject down while the pointer rests on the row.
                addSubview(quickActions)
                // The time's place grows to hold them, so the sender ends before them rather than under them.
                timeSlot = date.widthAnchor.constraint(
                    greaterThanOrEqualToConstant: quickActions.intrinsicContentSize.width)
                timeSlot?.isActive = true
                setNeedsLayout()
            }
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
        // The time keeps to the trailing edge of its place while that place is widened for the quick actions.
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        date.textAlignment = rightToLeft ? .left : .right
        super.layoutSubviews()
        guard let quickActions else { return }
        // The time sits in nested stacks, which place it only in their own passes, outermost first.
        let stacks = sequence(first: date.superview) { $0?.superview }.prefix { $0 != nil && $0 !== self }
        for stack in stacks.reversed() { stack?.layoutIfNeeded() }
        // Centered on the time's line, at its trailing edge, and rising into the row's top margin rather than
        // reaching the subject when it is taller than the line.
        let time = date.convert(date.bounds, to: self)
        let size = quickActions.intrinsicContentSize
        quickActions.frame = CGRect(
            x: rightToLeft ? time.minX : time.maxX - size.width,
            y: max(min(time.midY - size.height / 2, time.maxY - size.height), 0),
            width: size.width, height: size.height)
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
        // Not required: the time's place widens for the quick actions. The sender hugs less and takes the rest.
        date.setContentHuggingPriority(.defaultHigh, for: .horizontal)
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
        let text = UIStackView(arrangedSubviews: [header, subject, preview])
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
