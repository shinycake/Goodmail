public import MailCore

/// Runs one window's navigation (`WindowNavigation`): every event goes through `send(_:)`, which moves the state,
/// has the screens show it (`MailScreens`), and does what the transition says beyond that. A conversation to open is
/// found in the list on show when it holds it, else in the store, off the main actor; the newest lookup replaces any
/// still under way.
public final class WindowNavigator {
    /// Reads a conversation's row from the store, off the main actor; `nil` when it isn't on the device.
    public typealias LookUp = @concurrent @Sendable (ThreadSummary.ID) async -> ThreadSummary?

    public private(set) var navigation: WindowNavigation
    /// The viewer's screens; `nil` while the window shows something else, as one conversation alone.
    public private(set) var screens: MailScreens?
    private let lookUp: LookUp
    /// The lookup under way, which a newer one replaces.
    private var arriving: Task<Void, Never>?
    /// What the window shows changed.
    public var stateChanged: (WindowState) -> Void = { _ in }
    /// Presents a screen over or beside the window, which moves nothing in it (`WindowNavigation.Effect.present`).
    public var present: (Route) -> Void = { _ in }
    /// A message window's conversation went, so the window goes once that can't be undone.
    public var leaveWindow: () -> Void = {}

    public init(showing state: WindowState, checking lists: WindowState.ListCheck, lookUp: @escaping LookUp) {
        navigation = WindowNavigation(showing: state, checking: lists)
        self.lookUp = lookUp
    }

    isolated deinit {
        arriving?.cancel()
    }

    /// What the window shows.
    public var state: WindowState { navigation.state }

    /// Shows the viewer in `split`, with new screens made by `makers`, in the place of any shown before.
    public func show(in split: MailSplitViewController, making makers: MailScreens.Makers) {
        let screens = MailScreens(state, row: navigation.foundRow, in: split, making: makers)
        screens.wentBack = { [weak self] in self?.send(.back(to: $0)) }
        self.screens = screens
    }

    /// The window no longer shows the viewer's screens, as before it is rebuilt or while it shows one conversation.
    public func leaveScreens() {
        screens = nil
    }

    /// The window changed width.
    public func arrangementChanged() {
        screens?.arrangementChanged()
    }

    /// Moves the window for `event`.
    public func send(_ event: WindowNavigation.Event) {
        let before = state
        let context = WindowNavigation.Context(
            arrangement: screens?.arrangement ?? .stack, afterRemoval: Preferences.afterRemoval)
        let effects = navigation.handle(event, in: context)
        if state != before, let screens {
            let showing: MailScreens.Showing =
                switch event {
                case .changed, .undone: .announced
                default: .quiet
                }
            if !screens.show(state, row: navigation.foundRow, showing) {
                // A reader that can't be made, as one whose account just went: the list it was read from shows.
                _ = navigation.handle(.back(to: .list), in: context)
                screens.show(state, row: nil, .quiet)
            }
        }
        if state != before { stateChanged(state) }
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: WindowNavigation.Effect) {
        switch effect {
        case .lookUp(let thread, let mailbox):
            find(thread, in: mailbox)
        case .present(let route):
            present(route)
        case .beginSearch(let query):
            screens?.whenSettled { [weak self] in (self?.screens?.list as? MailboxViewController)?.beginSearch(query) }
        case .showList:
            screens?.split.showList()
        case .showPicked(let count):
            screens?.showPicked(count)
        case .leaveWindow:
            leaveWindow()
        }
    }

    /// Finds `thread` to open in `mailbox`: at once from the list on show when it holds it, else from the store.
    private func find(_ thread: ThreadSummary.ID, in mailbox: Mailbox) {
        arriving?.cancel()
        arriving = nil
        if let front = screens?.front, let row = front.summary(of: thread) {
            return send(.found(row, in: mailbox, rows: front.frontRows))
        }
        arriving = Task { @concurrent [weak self, lookUp] in
            let row = await lookUp(thread)
            await self?.arrived(row, as: thread, in: mailbox)
        }
    }

    /// The store's answer for `thread`, unless a newer lookup replaced this one. Called on the lookup's own task, which
    /// only the main actor cancels, so the check and what follows can't be split by a newer lookup.
    private func arrived(_ row: ThreadSummary?, as thread: ThreadSummary.ID, in mailbox: Mailbox) {
        guard !Task.isCancelled else { return }
        arriving = nil
        guard let row else { return send(.missing(thread)) }
        send(.found(row, in: mailbox, rows: screens?.front?.frontRows ?? []))
    }
}
