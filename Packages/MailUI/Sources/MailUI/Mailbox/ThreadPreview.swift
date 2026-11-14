import MailCore
import UIKit

/// The card a row lifts into when touched and held: who wrote last and when, the subject, and as much of the
/// newest message as the list knows. Tapping it opens the thread.
final class ThreadPreviewViewController: UIViewController {
    private let thread: ThreadSummary
    private let dateText: String

    init(thread: ThreadSummary, dateText: String) {
        self.thread = thread
        self.dateText = dateText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Narrow enough for the smallest iPhone, so UIKit never narrows it and clips the text it was measured for.
    private static let width: CGFloat = 340
    private static let insets = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 24, trailing: 20)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let sender = label(.headline, color: .label)
        sender.setContentText(thread.sender.displayName, alignedToContent: false)
        let date = label(.subheadline, color: .secondaryLabel)
        date.text = dateText
        date.setContentHuggingPriority(.required, for: .horizontal)
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        let header = UIStackView(arrangedSubviews: [sender, date])
        header.spacing = 8
        header.alignment = .firstBaseline

        let subject = label(.title3, color: .label)
        subject.font = subject.font.withWeight(.semibold)
        subject.numberOfLines = 3
        subject.setSubjectText(thread.subject.isEmpty ? ThreadRowMetrics.noSubject : thread.subject)

        let snippet = label(.body, color: .secondaryLabel)
        snippet.numberOfLines = 8
        snippet.setContentText(thread.snippet)

        let stack = UIStackView(arrangedSubviews: [header, subject] + (thread.snippet.isEmpty ? [] : [snippet]))
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(12, after: subject)
        stack.directionalLayoutMargins = Self.insets
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // One element for VoiceOver, read in the order the card shows it.
        view.isAccessibilityElement = true
        view.accessibilityLabel = [thread.sender.displayName, dateText, subject.text, thread.snippet]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")

        preferredContentSize = stack.systemLayoutSizeFitting(
            CGSize(width: Self.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    }

    private func label(_ style: UIFont.TextStyle, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        return label
    }
}
