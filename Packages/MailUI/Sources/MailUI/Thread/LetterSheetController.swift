import MailCore
import UIKit

/// One message of a chat in full, as its letter card, in a sheet over the conversation. Follows the thread's view
/// model, so allowing remote images or new data shows here at once.
final class LetterSheetController: UIViewController {
    private let viewModel: ThreadViewModel
    private let message: Message.ID
    private let card: MessageCardView
    private let scrollView = UIScrollView()

    /// `openAttachment` opens a file from the card, with a callback that shows its download.
    init(
        viewModel: ThreadViewModel, message: Message.ID, openURL: @escaping (URL) -> Void,
        openAttachment: @escaping (Attachment, _ loading: @escaping (Bool) -> Void) -> Void
    ) {
        self.viewModel = viewModel
        self.message = message
        card = MessageCardView(attachmentData: viewModel.attachmentData)
        super.init(nibName: nil, bundle: nil)
        card.openURL = openURL
        card.onAllowRemoteContent = { [weak viewModel] in viewModel?.allowRemoteContent(in: message) }
        card.onOpenAttachment = { [weak card] attachment in
            openAttachment(attachment) { card?.setLoading($0, for: attachment) }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(card)
        let readable = scrollView.readableContentGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            card.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
        ])
    }

    override func updateProperties() {
        super.updateProperties()
        guard let shown = viewModel.messages.first(where: { $0.id == message }) else { return }
        title = shown.subject
        card.configure(
            shown, dateText: viewModel.dateText(for: shown), accountEmail: viewModel.accountEmail,
            accountColor: viewModel.accountColor.uiColor,
            allowsRemoteContent: viewModel.remoteContentAllowed.contains(message))
    }
}
