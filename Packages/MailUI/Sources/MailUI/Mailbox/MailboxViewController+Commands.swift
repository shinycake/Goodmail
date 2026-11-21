public import MailCore
import UIKit

/// A mailbox's list starts a message, fetches mail, searches, steps through its threads, switches Inbox categories,
/// erases Trash and acts on several picked threads from the menu bar and the keyboard.
extension MailboxViewController: CommandScreen {
    public func answer(to command: MailCommand) -> CommandAnswer {
        if let sender = senderAnswer(to: command) { return sender }
        if let several = answerForSeveral(command) { return several }
        if let shortcut = command.rowShortcut { return answer(to: shortcut) }
        if let filtering = answerForFilter(command) { return filtering }
        if let category = command.category {
            guard let shown = viewModel.category else { return .notHere }
            return .ready(perform: { [weak self] in self?.show(category) }, isOn: category == shown)
        }
        switch command {
        case .newMessage:
            return .ready(perform: { [viewModel] in viewModel.compose() })
        case .getMail:
            // As pull to refresh: the view model owns the sync, and its failure shows on the health board.
            return .ready(perform: { [viewModel] in Task { await viewModel.refresh() } })
        case .search:
            guard let search else { return .unavailable }
            // Typing goes straight into the field, as after a tap on it.
            return .ready(perform: {
                search.isActive = true
                search.searchBar.becomeFirstResponder()
            })
        case .previousThread, .nextThread:
            return .offering(step(by: command == .nextThread ? 1 : -1))
        case .openInNewWindow:
            guard UIApplication.shared.supportsMultipleScenes, !isEditing, let id = selectedIDs.first else {
                return .unavailable
            }
            return .ready(perform: { [viewModel] in viewModel.openInNewWindow(id) })
        case .eraseTrash:
            guard viewModel.isTrash else { return .notHere }
            let ids = dataSource.snapshot().itemIdentifiers
            guard viewModel.actions != nil, !ids.isEmpty else { return .unavailable }
            // As Delete Forever with nothing selected: it asks first.
            return .ready(perform: { [weak self] in self?.perform(.deleteForever, on: ids) })
        default:
            return .notHere
        }
    }

    /// Opens the thread `offset` rows from the open one, selecting its row, or `nil` past either end or while
    /// selecting several.
    private func step(by offset: Int) -> (() -> Void)? {
        guard !isEditing, let target = viewModel.thread(offset, from: selectedIDs.first),
            let indexPath = dataSource.indexPath(for: target)
        else { return nil }
        return { [weak self] in
            guard let self else { return }
            guard !picksWithPointer else {
                collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
                return viewModel.click(target, .plain)
            }
            collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .centeredVertically)
            reportTouchPick()
            viewModel.open(target)
        }
    }
}

// MARK: - Several threads

extension MailboxViewController {
    /// What a mail command does to several picked threads: what their context menu offers (`ThreadMenu(several:)`),
    /// counted in the title where Mail counts, as "Archive 3 Conversations". `nil` unless several are picked.
    fileprivate func answerForSeveral(_ command: MailCommand) -> CommandAnswer? {
        guard case .several = viewModel.selection else { return nil }
        let ids = selectedIDs
        let threads = ids.compactMap { threadsByID[$0] }
        guard !threads.isEmpty, viewModel.actions != nil, ThreadMenu.Item.severalCommands.contains(command) else {
            return nil
        }
        let menu = ThreadMenu(
            several: threads, in: viewModel.mailbox, pin: viewModel.pinning(ids),
            opensWindows: UIApplication.shared.supportsMultipleScenes)
        guard let item = menu.sections.joined().first(where: { $0.isDone(by: command) }) else { return .unavailable }
        let done: () -> Void = { [weak self] in
            if self?.isEditing == true { self?.setEditing(false, animated: true) }
        }
        let viewModel = viewModel
        switch item {
        case .perform(let action):
            return .ready(
                perform: { [weak self] in self?.perform(action, on: ids, then: done) },
                title: Self.title(of: action, count: ids.count))
        case .pin(let pin):
            return .ready(
                perform: {
                    viewModel.pin(ids, pin)
                    done()
                }, title: PinPresentation.title(pin))
        case .move:
            return .ready(perform: {
                viewModel.move(ids)
                done()
            })
        case .changeLabels:
            return .ready(perform: {
                viewModel.changeLabels(of: ids)
                done()
            })
        case .snooze:
            return .ready(perform: { [weak self] in
                guard let self else { return }
                LaterPickerViewController.presentSnooze(
                    from: self, initial: LaterTime.snoozeChoices(at: .now).first?.date
                ) { date in
                    viewModel.snooze(ids, until: date)
                    done()
                }
            })
        case .answer, .openInNewWindow:
            return .unavailable
        }
    }

    /// `action`'s title for `count` threads, counted for the actions Mail counts.
    private static func title(of action: ThreadAction, count: Int) -> String {
        if action == .archive {
            return String(
                localized: "Archive \(count) Conversations", table: "Keyboard", bundle: .module,
                comment: "Menu bar command for several picked conversations")
        }
        if action == .trash {
            return String(
                localized: "Move \(count) Conversations to Trash", table: "Keyboard", bundle: .module,
                comment: "Menu bar command for several picked conversations")
        }
        if action == .markRead(true) {
            return String(
                localized: "Mark \(count) Conversations as Read", table: "Keyboard", bundle: .module,
                comment: "Menu bar command for several picked conversations")
        }
        if action == .markRead(false) {
            return String(
                localized: "Mark \(count) Conversations as Unread", table: "Keyboard", bundle: .module,
                comment: "Menu bar command for several picked conversations")
        }
        return action.title
    }
}

extension ThreadMenu.Item {
    /// Whether this item of the menu for several threads is what `command` does to them.
    fileprivate func isDone(by command: MailCommand) -> Bool {
        switch (command, self) {
        case (.archive, .perform(let action)): action == .archive
        case (.trash, .perform(let action)): action == .trash
        case (.reportSpam, .perform(let action)): action == .reportSpam
        case (.markRead, .perform(let action)): [.markRead(true), .markRead(false)].contains(action)
        case (.star, .perform(let action)): [.star(true), .star(false)].contains(action)
        case (.mute, .perform(let action)): [.mute, .unmute].contains(action)
        case (.pin, .pin), (.move, .move), (.changeLabels, .changeLabels), (.snooze, .snooze): true
        default: false
        }
    }

    /// The commands the menu for several threads has an item for.
    fileprivate static let severalCommands: Set<MailCommand> = [
        .archive, .trash, .reportSpam, .markRead, .star, .mute, .pin, .move, .changeLabels, .snooze,
    ]
}
