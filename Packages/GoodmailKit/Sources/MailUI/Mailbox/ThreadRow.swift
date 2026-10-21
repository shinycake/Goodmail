import MailCore
import UIKit

/// A mailbox row: sender and time, the subject in New York, then the preview. The account badge marks unread.
struct ThreadRowConfiguration: UIContentConfiguration, Equatable {
    var thread: ThreadSummary
    var dateText: String
    var accountColor: UIColor
    var previewLines = 2

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
    private let subject = UILabel()
    private let preview = UILabel()

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

        let header = UIStackView(arrangedSubviews: [sender, date])
        header.spacing = 8
        header.alignment = .firstBaseline
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
    }

    private func apply() {
        let thread = current.thread
        let name = thread.sender.displayName
        sender.font = .preferredFont(forTextStyle: .body).withWeight(thread.isUnread ? .semibold : .regular)
        sender.setContentText(name, alignedToContent: false)
        date.text = current.dateText
        let subjectText = thread.subject.isEmpty ? ThreadRowMetrics.noSubject : thread.subject
        subject.setSubjectText(subjectText)
        preview.setContentText(thread.snippet)
        preview.numberOfLines = current.previewLines
        preview.isHidden = current.previewLines == 0 || thread.snippet.isEmpty
        avatar.configure(name: name, badge: thread.isUnread ? current.accountColor : nil)

        accessibilityLabel = [
            thread.isUnread ? String(localized: "Unread", bundle: .module, comment: "VoiceOver: thread state") : nil,
            name, subjectText, current.dateText, preview.isHidden ? nil : thread.snippet,
        ].compactMap(\.self).joined(separator: ", ")
    }
}

enum ThreadRowMetrics {
    static let insets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    static let avatarSpacing: CGFloat = 12
    /// Where separators start, so they line up with the text rather than the avatar.
    static var textLeadingInset: CGFloat { insets.leading + MonogramView.diameter + avatarSpacing }
    static var noSubject: String {
        String(localized: "(No Subject)", bundle: .module, comment: "Shown in place of an empty email subject")
    }
}

extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
