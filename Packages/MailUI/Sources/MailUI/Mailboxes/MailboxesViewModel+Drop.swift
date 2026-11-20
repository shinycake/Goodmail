import MailCore

/// Conversations dragged from the list onto a row of the sidebar.
extension MailboxesViewModel {
    /// What dropping `dragged` on `destination` does; `adding` is the reader holding the option key.
    func drop(of dragged: [DraggedThread], onto destination: Destination, adding: Bool) -> MailDrop {
        guard actions != nil, case .mailbox(let target) = destination, let source = dragged.first?.mailbox else {
            return .refused
        }
        return MailDrop(
            dragging: dragged.map(\.id), from: source, onto: target, among: accounts, adding: adding)
    }

    /// Carries out `drop`, with the toast that undoes it.
    func perform(_ drop: MailDrop, of dragged: [DraggedThread], onto destination: Destination) {
        guard let actions, case .mailbox(let target) = destination, let source = dragged.first?.mailbox else { return }
        let ids = dragged.map(\.id)
        let name = target.title(labels: directory.labels)
        switch drop {
        case .refused: break
        case .perform(let action): actions.perform(action, on: ids)
        case .move(let place): actions.move(ids, to: place, named: name, from: source)
        case .addLabel(let label): actions.addLabel(label, named: name, to: ids)
        }
    }
}
