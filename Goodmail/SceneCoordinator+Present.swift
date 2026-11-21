import MailCore
import MailStore
import MailUI
import UIKit

extension SceneCoordinator {
    /// Presents `presentation` over or beside the window, which moves nothing the window shows: the composer, the
    /// label and move pickers, Settings, a sign-in, the smart mailbox editor, or another window. Where it goes is the
    /// window's interaction style's to say for compose, Settings and a conversation's own window (ADR-035).
    func present(_ presentation: Presentation) {
        switch presentation {
        case .newWindow(let id, let mailbox):
            // iPhone Duo opens new windows only on its inner display, so closed, the thread opens here instead.
            let opened = shown.opening(Reading(id, in: mailbox), as: window.interactionStyle.threadWindowLayout)
            openWindow(showing: opened) { [weak self] in self?.handle(.thread(id, in: mailbox)) }
        case .changeLabels(let ids):
            presentLabelPicker(for: ids)
        case .move(let ids, let mailbox):
            guard let presenter = topViewController() else { return }
            let database = model.database
            let picker = MoveViewController(
                viewModel: MoveViewModel(
                    threads: ids, from: mailbox, labels: { (try? database.labels(for: $0)) ?? [] },
                    editor: { [model] in model.labelEditor(for: $0) }, actions: actions))
            let navigation = UINavigationController(rootViewController: picker)
            navigation.sheetPresentationController?.detents = [.medium(), .large()]
            presenter.present(navigation, animated: true)
        case .settings(let page):
            switch window.interactionStyle.settingsPlacement {
            case .cover: showSettings(at: page)
            case .ownWindow: SettingsWindowCoordinator.open(at: page, from: window.windowScene)
            }
        case .signInAgain(let id):
            signInAgain(id)
        case .answer(let id, let answer):
            compose(answering: id, with: answer)
        case .draft(let id, let source):
            finishDraft(in: id, from: source)
        case .newSmartMailbox(let query):
            smartMailboxFlow.create(from: query)
        case .editSmartMailbox(let id):
            smartMailboxFlow.edit(id)
        case .compose(let draft):
            compose(draft)
        case .receiveTransfer(let code):
            receiveTransfer(code: code)
        }
    }

    /// The label picker for `ids`, once their rows and their account's labels are read off the main actor. A newer one
    /// replaces it.
    private func presentLabelPicker(for ids: [ThreadSummary.ID]) {
        pickingLabels?.cancel()
        pickingLabels = Task { [weak self, database = model.database] in
            let read = await Self.labelPicking(ids, in: database)
            guard !Task.isCancelled, let self, let (threads, labels) = read,
                let account = threads.first?.id.accountID, let presenter = topViewController()
            else { return }
            let actions = actions
            let picker = LabelPickerViewController(
                labels: labels, threads: threads, editor: model.labelEditor(for: account)
            ) { action in
                actions.perform(action, on: ids)
            }
            let navigation = UINavigationController(rootViewController: picker)
            navigation.sheetPresentationController?.detents = [.medium(), .large()]
            presenter.present(navigation, animated: true)
        }
    }

    /// The rows of `ids` on the device and their account's labels, or `nil` when none is or the labels can't be read.
    @concurrent
    private nonisolated static func labelPicking(_ ids: [ThreadSummary.ID], in database: MailDatabase) async -> (
        [ThreadSummary], [MailLabel]
    )? {
        let threads = ids.compactMap { try? database.thread($0) }
        guard let account = threads.first?.id.accountID, let labels = try? database.labels(for: account) else {
            return nil
        }
        return (threads, labels)
    }

    /// The composer with `answer` to the thread's newest message, once it is fetched. A newer answer or draft
    /// replaces it.
    private func compose(answering id: ThreadSummary.ID, with answer: Answer) {
        guard let account = model.accounts.first(where: { $0.id == id.accountID }) else { return }
        answering?.cancel()
        answering = Task { [weak self, model] in
            let draft = try? await answer.draft(
                answering: model.messagesToAnswer(in: id), accountEmail: account.email, aliases: account.aliases,
                wording: .localized)
            guard !Task.isCancelled, let self else { return }
            if let draft {
                handle(.compose(draft))
            } else {
                topViewController()?.present(UIAlertController.answerUnavailable(), animated: true)
            }
        }
    }

    /// The composer with the draft that is the thread's newest message, once it is fetched, or the thread itself when
    /// its newest message is no draft, as one sent or deleted since: from outside, as Continue Draft, it is revealed in
    /// Drafts or said to be gone. A newer answer or draft replaces it.
    private func finishDraft(in id: ThreadSummary.ID, from source: RouteSource) {
        guard let account = model.accounts.first(where: { $0.id == id.accountID }) else { return }
        answering?.cancel()
        answering = Task { [weak self, model] in
            let newest = try? await model.messagesToAnswer(in: id).last
            guard !Task.isCancelled, let self else { return }
            if let newest, newest.labelIDs.contains(SystemLabel.draft) {
                handle(.compose(Draft.editing(newest, aliases: account.aliases)), from: source)
            } else {
                handle(.thread(id, in: .drafts), from: source)
            }
        }
    }
}
