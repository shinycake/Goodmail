import MailCore
import UIKit

/// On a desktop window the reader's controls sit in the window's toolbar over the letter, in place of the bar at the
/// bottom: what takes the conversation away, then how to answer it, then the layout and More, with search at the end
/// (the list lends its field to this column). Each button names itself and its keys when the pointer rests on it.
extension ThreadViewController {
    /// Where the reader's controls are: the bar at the bottom, or the window's toolbar over the letter.
    enum Bars {
        case bottom
        case window(WindowToolbar)
    }

    /// The window's toolbar as laid out: whether Edit Draft has Reply's place, and More, which the share sheet points
    /// from since Share is in it.
    struct WindowToolbar {
        let answersDraft: Bool
        let more: UIBarButtonItem
    }

    var usesWindowToolbar: Bool { traitCollection.interactionStyle == .desktop }

    func placeWindowToolbar() -> WindowToolbar {
        let away = [
            commandItem(.archive, symbol: ThreadAction.archive.symbol) { [weak self] in
                self?.viewModel.perform(.archive)
            },
            viewModel.isInTrash
                ? deleteForeverItem()
                : commandItem(.trash, symbol: ThreadAction.trash.symbol) { [weak self] in
                    self?.viewModel.perform(.trash)
                },
            commandItem(.move, symbol: "folder") { [weak self] in self?.viewModel.move() },
            snoozeItem(),
        ]
        let answersDraft = viewModel.draft != nil
        // Its own Edit Draft: the bar at the bottom, hidden here, keeps the other, and an item shows in one bar.
        let answers =
            [answersDraft ? makeEditDraftItem() : answerItem(.reply, command: .reply)]
            + [answerItem(.replyAll, command: .replyAll), answerItem(.forward, command: .forward)]
        BarToolTips.set(layoutItem, MailCommand.switchLayout.toolTip)
        let more = moreItem()
        navigationItem.trailingItemGroups = [
            .fixedGroup(items: away), .fixedGroup(items: answers), .fixedGroup(items: [layoutItem]),
            .fixedGroup(items: [more]),
        ]
        return WindowToolbar(answersDraft: answersDraft, more: more)
    }

    /// Edit Draft takes Reply's place while the newest message is an unsent draft.
    func updateWindowToolbar() {
        guard case .window(let toolbar) = bars, toolbar.answersDraft != (viewModel.draft != nil) else { return }
        placeShareItem()
    }

    private func commandItem(
        _ command: MailCommand, symbol: String, action: @escaping () -> Void
    ) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            title: command.title, image: UIImage(systemName: symbol), primaryAction: UIAction { _ in action() })
        BarToolTips.set(item, command.toolTip)
        return item
    }

    private func answerItem(_ answer: Answer, command: MailCommand) -> UIBarButtonItem {
        commandItem(command, symbol: answer.symbol) { [weak self] in self?.viewModel.answer(answer) }
    }

    private func snoozeItem() -> UIBarButtonItem {
        let item = UIBarButtonItem.snooze(from: self) { [weak self] in self?.viewModel.snooze(until: $0) }
        BarToolTips.set(item, MailCommand.snooze.toolTip)
        return item
    }

    /// Mark as Unread, Star, Labels, Pin, Mute, Report Spam and Share: what the window's toolbar has no room for.
    private func moreItem() -> UIBarButtonItem {
        let marks = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { return completion([]) }
            let star: ThreadAction = .star(!viewModel.isStarred)
            completion([
                UIAction(
                    title: ThreadAction.markRead(false).title,
                    image: UIImage(systemName: ThreadAction.markRead(false).symbol)
                ) { [weak self] _ in self?.viewModel.perform(.markRead(false)) },
                UIAction(title: star.title, image: UIImage(systemName: star.symbol)) { [weak self] _ in
                    self?.viewModel.perform(star)
                },
            ])
        }
        let organize = UIBarButtonItem.organize(
            move: { [weak self] in self?.viewModel.move() },
            changeLabels: { [weak self] in self?.viewModel.changeLabels() },
            pinning: { [weak self] in self?.viewModel.isPinned == false },
            pin: { [weak self] in self?.viewModel.pin($0) },
            mute: { [weak self] in self?.viewModel.muteAction },
            perform: { [weak self] in self?.viewModel.perform($0) })
        let spam = UIAction(
            title: ThreadAction.reportSpam.title, image: UIImage(systemName: ThreadAction.reportSpam.symbol)
        ) { [weak self] _ in self?.viewModel.perform(.reportSpam) }
        let sections: [UIMenuElement] = [
            UIMenu(options: .displayInline, children: [marks]),
            UIMenu(options: .displayInline, children: (organize.menu?.children ?? []) + [spam]),
            shareItem.menu.map { UIMenu(options: .displayInline, children: [$0]) },
        ].compactMap(\.self)
        let title = String(
            localized: "More", table: "Thread", bundle: .module,
            comment: "Toolbar menu: more things to do with the conversation")
        let item = UIBarButtonItem(
            title: title, image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: sections))
        BarToolTips.set(item, title)
        return item
    }
}
