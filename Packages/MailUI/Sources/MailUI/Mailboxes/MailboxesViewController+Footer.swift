import MailCore
import UIKit

/// A desktop sidebar ends in a quiet footer rather than a toolbar: Settings is in the menu bar there, and the footer
/// tells how mail is coming in, with New Label at its end.
extension MailboxesViewController {
    var showsFooter: Bool {
        style == .sidebar && syncFooter != nil && traitCollection.interactionStyle == .desktop
    }

    func installFooter() {
        guard case .sidebar(footer: .none) = chrome, showsFooter, let syncFooter else { return }
        let footer = SidebarFooterView(newLabel: newLabelItem())
        footer.onProblem = { [weak self] notice in self?.explain(notice, with: syncFooter) }
        wear(footer)
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        footer.show(syncFooter.status)
        // The rows' update reads the board only while the footer is there, so it starts watching the board now.
        setNeedsUpdateProperties()
        view.layoutIfNeeded()
        // The rows scroll clear of the footer, as they would of a toolbar.
        collectionView.contentInset.bottom = footer.bounds.height
        collectionView.verticalScrollIndicatorInsets.bottom = footer.bounds.height
    }

    /// Asks about the account's problem, with its fix, as the list's toolbar does on touch.
    private func explain(_ notice: AccountProblemNotice, with source: SyncFooterSource) {
        let alert = UIAlertController.accountProblems([notice]) { [weak self] notice in
            self?.fix(notice, with: source)
        }
        present(alert, animated: true)
    }
}
