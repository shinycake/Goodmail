import MailCore

/// ⌘1 to ⌘9 open the sidebar's first rows from the list, and ⌃⌘1 to ⌃⌘9 move the picked conversations to them.
extension MailboxViewController {
    func answer(to shortcut: RowShortcut) -> CommandAnswer {
        guard let sidebar = viewModel.sidebar() else { return .notHere }
        switch shortcut {
        case .goTo:
            return sidebar.answer(toOpening: shortcut)
        case .moveTo:
            let picked = selectedIDs.map { DraggedThread(id: $0, mailbox: viewModel.mailbox) }
            return sidebar.answer(toMoving: picked, to: shortcut)
        }
    }

    /// Turn Filter On or Off, and each choice of Filter by, checked while the filter asks for it. `nil` for any other
    /// command, and where this list isn't filtered.
    func answerForFilter(_ command: MailCommand) -> CommandAnswer? {
        guard viewModel.offersFilter else { return nil }
        let filter = viewModel.filter
        if command == .toggleFilter {
            return .ready(
                perform: { [weak self] in self?.setFilter(filter.toggled()) },
                title: filter.isOn ? FilterButton.turnOffMenuTitle : FilterButton.turnOnMenuTitle)
        }
        guard let option = command.filterOption else { return nil }
        return .ready(
            perform: { [weak self] in self?.setFilter(filter.toggling(option)) }, isOn: filter.asks(for: option))
    }
}
