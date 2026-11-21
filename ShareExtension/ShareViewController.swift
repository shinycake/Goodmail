import MailCore
import MailStore
import MailUI
import UIKit

/// The Share extension's sheet: Goodmail's own composer, holding what the other app shared, sending from any
/// account. A message goes at once from here while the sheet shows it going; whatever can't finish waits in the
/// app's queue, and the sheet says so before it closes (`ShareSession`). As it is written, the message is kept for the
/// app as a draft (`DraftKeeper`), so the sheet going away unasked loses nothing.
final class ShareViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private enum Stage {
        /// Not on the screen yet.
        case idle
        /// Opening the mail database and reading what was shared.
        case opening(Task<Void, Never>)
        case writing(ShareSession, ComposeWindowController)
        /// The writer's errand is under way; the composer stays under the overlay until it is done.
        case working(ShareSession, ComposeWindowController, ShareProgressView, Task<Void, Never>)
        /// The last writes of the message as written are finishing; the request ends after them.
        case closing(Task<Void, Never>)
        /// The request was completed or cancelled.
        case finished
    }

    private var stage = Stage.idle
    private let opening = UIActivityIndicatorView(style: .large)
    /// Reading a long video or a file from iCloud can take a while, so the sheet can be closed meanwhile.
    private lazy var cancelOpening = UIButton(
        configuration: .glass(),
        primaryAction: UIAction(
            title: String(localized: "Cancel", comment: "Closes the share sheet while it reads what was shared")
        ) { [weak self] _ in self?.finish(sent: false) })

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // A swipe down saves the message as a draft rather than closing the sheet as it is
        // (`presentationControllerDidAttemptToDismiss`).
        isModalInPresentation = true
        opening.accessibilityLabel = String(
            localized: "Loading", comment: "What the share sheet's spinner says to VoiceOver")
        opening.startAnimating()
        for view in [opening, cancelOpening] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(view)
        }
        NSLayoutConstraint.activate([
            opening.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            opening.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cancelOpening.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            cancelOpening.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }

    /// Reading starts once the sheet is up, so an alert about what was shared has a screen to show on.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard case .idle = stage else { return }
        presentationController?.delegate = self
        let request = SharedItems.Request(extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? [])
        stage = .opening(
            Task { [weak self] in
                async let session = Result { try await ShareSession.open() }
                let shared = await SharedItems.load(request, limit: ComposeViewModel.attachmentLimit)
                self?.opened(await session, with: shared)
            })
    }

    private func opened(_ session: Result<ShareSession, any Error>, with shared: SharedItems.Loaded) {
        guard case .opening = stage else { return }
        opening.stopAnimating()
        cancelOpening.removeFromSuperview()
        guard case .success(let session) = session else {
            return explain(.unavailable) { [weak self] in self?.finish(sent: false) }
        }
        guard let account = session.accounts.first else {
            return explain(.noAccounts) { [weak self] in self?.finish(sent: false) }
        }
        // The share sheet has no close button of its own, so the composer keeps its Close.
        let window = ComposeWindowController(
            composer: composer(for: shared.content, from: account, in: session), placement: .sheet
        ) { [weak self] in self?.composerClosed() }
        addChild(window)
        window.view.frame = view.bounds
        window.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(window.view)
        window.didMove(toParent: self)
        stage = .writing(session, window)
        if shared.leftOutFiles { window.composer?.tooLarge() }
    }

    private func composer(for shared: SharedContent, from account: Account, in session: ShareSession)
        -> ComposeViewController
    {
        let database = session.database
        let suggester = RecipientSuggester(
            writtenIn: { try database.contacts(matching: $0) }, addressBook: SystemAddressBook())
        let draft = Draft(accountID: account.id, subject: shared.subject, attachments: shared.files)
        return ComposeViewController(
            viewModel: ComposeViewModel(
                draft: draft, accountEmail: account.email, senders: session.accounts, shared: shared.body,
                signature: { try? database.signature(for: $0) },
                suggest: { await suggester.suggestions(for: $0) },
                // As written, the app saves it in Drafts after its usual wait; leaving the screen, at once, in case
                // the sheet doesn't come back. The writer's own Save Draft goes from here.
                saveDraft: { [weak self] draft, save in
                    switch save {
                    case .now: self?.start(.saveDraft, for: draft)
                    case .asWritten:
                        session.drafts.keep(.written(draft, by: OutgoingMessage.autosave(draft, at: .now).sendAt))
                    case .leaving: session.drafts.keep(.written(draft, by: .now))
                    }
                },
                deleteDraft: { session.drafts.keep(.deleted($0)) },
                send: { [weak self] draft, time in
                    switch time {
                    case .now: self?.start(.send, for: draft)
                    case .at(let date): self?.start(.schedule(date), for: draft)
                    }
                }))
    }

    /// Sends, saves or schedules the message, with the composer held under the overlay until that's done.
    private func start(_ errand: ShareSession.Errand, for draft: Draft) {
        guard case .writing(let session, let window) = stage else { return }
        let progress = ShareProgressView(errand)
        progress.show(over: view)
        stage = .working(
            session, window, progress,
            Task { [weak self] in
                let outcome = await Result { try await session.run(errand, for: draft) }
                self?.finished(errand, with: outcome, in: session)
            })
    }

    private func finished(
        _ errand: ShareSession.Errand, with outcome: Result<ShareSession.Ending, any Error>,
        in session: ShareSession
    ) {
        guard case .working(_, let window, let progress, _) = stage else { return }
        switch (outcome, errand) {
        case (.success(.delivered(.done)), _), (.success, .schedule):
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            finish(sent: true)
        case (.success(.delivered(.handedOver(let delivery))), _):
            explain(ShareNotice(errand, leftAs: delivery)) { [weak self] in self?.finish(sent: true) }
        case (.success(.waitingForSignIn), _):
            explain(.signedOut(errand)) { [weak self] in self?.finish(sent: true) }
        case (.failure(let error as ImmediateDelivery.NotKept), _) where error.mayHaveGone:
            // Sending it again could send it twice.
            explain(.mayHaveGone) { [weak self] in self?.finish(sent: true) }
        case (.failure, _):
            // Kept nowhere, and not gone: the writer is back in the message, to try again.
            progress.removeFromSuperview()
            stage = .writing(session, window)
            window.composer?.resumeAfterFailure()
            explain(.notKept)
        }
    }

    /// A swipe down on the sheet: a message with something in it is saved as a draft, one without closes.
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        guard case .writing(_, let window) = stage else { return }
        window.composer?.dismissKeepingDraft()
    }

    /// The composer closed without an errand: the message was deleted or closed unchanged.
    private func composerClosed() {
        guard case .writing = stage else { return }
        finish(sent: false)
    }

    private func explain(_ notice: ShareNotice, then next: (() -> Void)? = nil) {
        let alert = UIAlertController(title: notice.title, message: notice.message, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(localized: "OK", comment: "Dismisses a note about the shared message"), style: .default
            ) { _ in next?() })
        // Over whatever the composer still shows, such as the Send Later picker on its way out.
        var presenter: UIViewController = self
        while let next = presenter.presentedViewController, !next.isBeingDismissed { presenter = next }
        presenter.present(alert, animated: true)
    }

    private func finish(sent: Bool) {
        switch stage {
        case .finished, .closing: return
        case .opening(let task):
            task.cancel()
            end(sent: sent)
        case .idle: end(sent: sent)
        case .writing(let session, _), .working(let session, _, _, _):
            stage = .closing(
                Task {
                    await session.drafts.settle()
                    self.end(sent: sent)
                })
        }
    }

    private func end(sent: Bool) {
        stage = .finished
        // Nothing is writing now, and iOS suspends the extension next: no database may hold a lock then (0xdead10cc).
        MailDatabase.suspendAll()
        if sent {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
