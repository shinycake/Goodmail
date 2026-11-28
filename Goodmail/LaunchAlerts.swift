import MailCore
import MailStore
import UIKit

/// The alerts the app shows once a launch, in the front viewer rather than in every window: each failed send, offered
/// to edit, retry or delete, and the first Gmail account whose sign-in can't delete forever, asked to sign in again.
/// Held by the model for every window, so a second window, or one opened later, doesn't show them again.
final class LaunchAlerts {
    private let database: OffMainDatabase
    private let signInsToRenew: () async -> [Account]
    private var ledger = LaunchAlertLedger<OutgoingMessage>()
    /// Only `viewerShowed()` changes it.
    private var state = State.waiting

    private enum State {
        /// No viewer has shown yet this launch.
        case waiting
        /// Following the failed sends, and checking the Gmail sign-ins once, from the first viewer on.
        case watching(failures: Task<Void, Never>, signIns: Task<Void, Never>)
    }

    init(database: OffMainDatabase, signInsToRenew: @escaping () async -> [Account]) {
        self.database = database
        self.signInsToRenew = signInsToRenew
    }

    isolated deinit {
        guard case .watching(let failures, let signIns) = state else { return }
        failures.cancel()
        signIns.cancel()
    }

    /// A viewer filled its window: the first one starts the watch, and a later one offers a failed send no window
    /// could show before.
    func viewerShowed() {
        switch state {
        case .waiting:
            state = .watching(
                failures: Task { [weak self, database] in
                    do {
                        for try await failed in database.failedMessages() { self?.failedNow(failed) }
                    } catch {}
                },
                signIns: Task { [signInsToRenew] in
                    guard let account = await signInsToRenew().first, !Task.isCancelled else { return }
                    MailWindows.frontViewer?.askToSignInAgain(account)
                })
        case .watching:
            offerFailure()
        }
    }

    private func failedNow(_ failed: [OutgoingMessage]) {
        ledger.failedNow(failed)
        offerFailure()
    }

    /// Offers the first failed send not shown yet in the front viewer, if it can show one now.
    private func offerFailure() {
        guard let message = ledger.nextFailure, MailWindows.frontViewer?.offerFailure(of: message) == true else {
            return
        }
        ledger.showed(message.id)
    }
}
