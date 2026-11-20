import MailCore
import UIKit

/// How the reader works with a pointer and a keyboard: the hovered link's address, zoom, find in the conversation,
/// and Quick Look and Save to Downloads on an attachment. Zoom and Quick Look follow the messages on show; the touch
/// windows reach them only from a keyboard or the menu bar.
extension ThreadViewController {
    /// The cards of the open letters in reading order, my replies on their way among them.
    var openCards: [MessageCardView] {
        stack.arrangedSubviews.compactMap { ($0 as? MessageCardView) ?? ($0 as? PendingLetterView)?.card }
    }

    func installReaderOverlays() {
        readerPill.translatesAutoresizingMaskIntoConstraints = false
        findBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(readerPill)
        view.addSubview(findBar)
        let safe = view.safeAreaLayoutGuide
        let findWidth = findBar.widthAnchor.constraint(equalToConstant: 520)
        findWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            readerPill.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            readerPill.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -12),
            readerPill.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            findBar.topAnchor.constraint(equalTo: safe.topAnchor, constant: Self.findBarGap),
            findBar.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            findBar.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 12),
            findBar.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -12),
            findWidth,
        ])
        find.targets = { [weak self] in self?.openCards ?? [] }
        find.onMatch = { [weak self] target, box in self?.reveal(box, in: target) }
        find.onChange = { [weak self] in self?.findBar.show($0) }
        findBar.onQuery = { [weak self] in self?.find.setQuery($0) }
        findBar.onStep = { [weak self] in self?.find.step(backwards: $0) }
        findBar.onDone = { [weak self] in self?.find.close() }
    }

    /// What a card does on a desktop window beyond touch: show hovered links and save attachments to Downloads.
    func wireDesktop(_ card: MessageCardView, message: Message.ID) {
        card.onHoverLink = { [weak self] in self?.readerPill.hover($0) }
        card.onSaveAttachment = { [weak self, weak card] attachment in
            self?.saveToDownloads(attachment, in: message) { card?.setLoading($0, for: attachment) }
        }
    }

    private static let findBarGap: CGFloat = 8
    private static let findBarHeight: CGFloat = 44

    /// How much of the top of the scroll view the find bar covers.
    private var findClearance: CGFloat {
        find.isOpen ? Self.findBarHeight + Self.findBarGap * 2 : 0
    }

    func showFind() {
        find.open()
        findBar.focus()
    }

    /// Scrolls the match, at `box` in `target`'s coordinates, into the middle of what shows, unless it shows already.
    private func reveal(_ box: CGRect, in target: UIView) {
        view.layoutIfNeeded()
        let match = target.convert(box, to: scrollView)
        let inset = scrollView.adjustedContentInset
        let top = scrollView.contentOffset.y + inset.top + findClearance
        let bottom = scrollView.contentOffset.y + scrollView.bounds.height - inset.bottom
        guard match.minY < top || match.maxY > bottom else { return }
        let wanted = match.midY - (bottom - top) / 2 - inset.top - findClearance
        let lowest = -inset.top
        let highest = max(lowest, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: min(highest, max(lowest, wanted))),
            animated: !SystemAccessibility.reducesMotion)
    }

    /// Find, zoom and Quick Look in the menu bar and from the keyboard. They apply to the letters, so the chat's
    /// bubbles leave them dimmed.
    func readerAnswer(to command: MailCommand) -> CommandAnswer {
        guard viewModel.layout == .classic else { return .unavailable }
        let zoom = ReaderZoomModel.shared
        switch command {
        case .findInConversation: return .ready(perform: { [weak self] in self?.showFind() })
        case .findNext, .findPrevious:
            guard find.canStep else { return .unavailable }
            let backwards = command == .findPrevious
            return .ready(perform: { [weak self] in self?.find.step(backwards: backwards) })
        case .zoomIn: return .offering(zoom.zoom.canZoomIn ? { zoom.zoomIn() } : nil)
        case .zoomOut: return .offering(zoom.zoom.canZoomOut ? { zoom.zoomOut() } : nil)
        case .actualSize: return .offering(zoom.zoom.isStandard ? nil : { zoom.reset() })
        case .quickLook:
            guard let selected = openCards.lazy.compactMap(\.selectedAttachment).first else { return .unavailable }
            return .ready(perform: selected.preview)
        default: return .notHere
        }
    }

    /// Copies the attachment into the Downloads folder and says so in the pill, or says why it couldn't.
    func saveToDownloads(_ attachment: Attachment, in message: Message.ID, loading: @escaping (Bool) -> Void) {
        downloads.save(
            attachment, file: { [viewModel] in try await viewModel.file(for: attachment, in: message) },
            loading: loading,
            finished: { [weak self] result in
                switch result {
                case .success:
                    let name = attachment.filename
                    self?.readerPill.announce(
                        String(
                            localized: "Saved “\(name)” to Downloads", table: "Thread", bundle: .module,
                            comment: "Pill at the bottom of the reader; the argument is the attachment's file name"))
                case .failure(let error):
                    self?.presentSaveFailure(error)
                }
            })
    }

    private func presentSaveFailure(_ error: any Error) {
        let alert = UIAlertController(
            title: String(
                localized: "Couldn’t Save Attachment", table: "Thread", bundle: .module,
                comment: "Alert title when an attachment can't be copied to Downloads"),
            message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(localized: "OK", table: "Thread", bundle: .module, comment: "Dismiss"), style: .default))
        (presentedViewController ?? self).present(alert, animated: true)
    }
}
