import Foundation
import MailCore
import Observation

/// The accounts on this device and the reader's choices.
@Observable
public final class SettingsViewModel {
    public private(set) var accounts: [Account]
    public private(set) var isAddingAccount = false
    /// The last add or remove that failed, for the view to show.
    public var error: (any Error)?
    public var undoSendSeconds: Int {
        didSet { Preferences.undoSendSeconds = undoSendSeconds }
    }

    @ObservationIgnored private let add: () async throws -> Bool
    @ObservationIgnored private let remove: (AccountID) async throws -> Void
    @ObservationIgnored private let reload: () -> [Account]
    @ObservationIgnored private let closed: () -> Void

    /// `add` signs in another account and returns `false` if the reader cancelled; `remove` takes an account and
    /// its mail off the device. `reload` reads the accounts back after either. `closed` runs once the screen is gone,
    /// however it was dismissed.
    public init(
        accounts: @escaping () -> [Account],
        add: @escaping () async throws -> Bool,
        remove: @escaping (AccountID) async throws -> Void,
        closed: @escaping () -> Void
    ) {
        self.accounts = accounts()
        undoSendSeconds = Preferences.undoSendSeconds
        reload = accounts
        self.add = add
        self.remove = remove
        self.closed = closed
    }

    public func addAccount() async {
        isAddingAccount = true
        defer { isAddingAccount = false }
        do {
            _ = try await add()
        } catch {
            self.error = error
        }
        accounts = reload()
    }

    public func removeAccount(_ id: AccountID) async {
        do {
            try await remove(id)
        } catch {
            self.error = error
        }
        accounts = reload()
    }

    func didClose() {
        closed()
    }

    /// "Off", or the wait as a short duration.
    static func undoSendTitle(_ seconds: Int) -> String {
        guard seconds > 0 else {
            return String(
                localized: "Undo Send: Off", defaultValue: "Off", bundle: .module, comment: "Undo Send is turned off")
        }
        return Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide))
    }
}
