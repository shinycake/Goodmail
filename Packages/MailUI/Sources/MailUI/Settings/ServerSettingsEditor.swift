import Foundation
import MailCore
import Observation

/// A password account's sign-in as the reader edits it in Settings: an Other Mail Account's servers and password, or
/// iCloud's app-specific password. Read from the device, changed here, and kept only once the servers accept it, as
/// when the account was added. Every state change happens in
/// `load()`, `submit()` and `save()`.
@MainActor
@Observable
public final class ServerSettingsEditor {
    /// What the account logs in with.
    public struct Login: Equatable, Sendable {
        /// `nil` for a service that sets its own servers, as iCloud does.
        public var settings: MailServerSettings?
        public var password: String

        public init(settings: MailServerSettings?, password: String) {
            self.settings = settings
            self.password = password
        }
    }

    /// What the screen edits, which names it.
    public enum Kind: Sendable {
        /// The servers and the password, for an account on any IMAP and SMTP server.
        case servers
        /// Only the app-specific password, for iCloud.
        case appPassword
    }

    /// Where the editor stands. `saved` is the login the device keeps, which `draft` started from.
    enum State: Equatable {
        case loading
        /// There is no login on the device to edit, as after the Keychain was reset.
        case loadFailed
        /// `failure` is why the last save didn't go through, shown until the next one.
        case editing(saved: Login, failure: OtherAccountStage.Failure?)
        /// Logging in to both servers with `login` before keeping it.
        case saving(saved: Login, login: Login)
        /// Kept: the screen can close.
        case saved
    }

    /// How to reach the account's login.
    public struct Service {
        public let kind: Kind
        public let load: () throws -> Login
        /// Logs in to the servers, then keeps the login. Throws `OtherAccountSignInFailure` when a server refuses
        /// or doesn't answer.
        public let save: (Login) async throws -> Void

        public init(kind: Kind, load: @escaping () throws -> Login, save: @escaping (Login) async throws -> Void) {
            self.kind = kind
            self.load = load
            self.save = save
        }
    }

    private(set) var state = State.loading
    /// The login as the reader has it now.
    var draft = Login(settings: nil, password: "")
    @ObservationIgnored let service: Service

    public init(service: Service) {
        self.service = service
    }

    var isSaving: Bool {
        if case .saving = state { true } else { false }
    }

    var failure: OtherAccountStage.Failure? {
        if case .editing(_, let failure) = state { failure } else { nil }
    }

    /// Whether Save has a complete change to check.
    var canSave: Bool {
        guard case .editing(let saved, _) = state else { return false }
        return draft != saved && draft.settings?.isFilledIn != false && !draft.password.isEmpty
    }

    func load() {
        guard state == .loading else { return }
        do {
            let login = try service.load()
            draft = login
            state = .editing(saved: login, failure: nil)
        } catch {
            state = .loadFailed
        }
    }

    /// Starts checking the draft; `save()` does the work once the state says so.
    func submit() {
        guard canSave, case .editing(let saved, _) = state else { return }
        state = .saving(saved: saved, login: draft)
    }

    /// Logs in with the login being saved, and keeps it when both servers accept it.
    func save() async {
        guard case .saving(let saved, let login) = state else { return }
        do {
            try await service.save(login)
            state = .saved
        } catch is CancellationError {
            state = .editing(saved: saved, failure: nil)
        } catch let failure as OtherAccountSignInFailure {
            if case .refused = failure { draft.password = "" }
            state = .editing(saved: saved, failure: .signIn(failure))
        } catch {
            state = .editing(saved: saved, failure: .other(error.localizedDescription))
        }
    }
}
