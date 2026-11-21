public import MailCore

/// Runs one window's navigation (`WindowNavigation`): every event goes through `send(_:)`, which moves the state,
/// has the screens show it (`MailScreens`), and does what the transition says beyond that. A conversation to open is
/// found in the list on show when it holds it, else in the store, off the main actor. The navigation says which lookup
/// it waits for (`pending`); one it no longer waits for is cancelled.
public final class WindowNavigator {
    /// Finds a conversation's row, off the main actor: in the store, or once from its service; `nil` when neither has it.
    public typealias LookUp = @concurrent @Sendable (ThreadSummary.ID) async -> ThreadSummary?

    public private(set) var navigation: WindowNavigation
    /// The viewer's screens; `nil` while the window shows something else, as one conversation alone.
    public private(set) var screens: MailScreens?
    private let lookUp: LookUp
    /// What the window knows now apart from what it shows: how it lays it out, from its width class, which holds
    /// before it is on screen, and the setting read at each change.
    private let context: () -> WindowNavigation.Context
    /// The store lookup under way, for `navigation.pending`.
    private var arriving: Task<Void, Never>?
    /// What the window shows changed.
    public var stateChanged: (WindowState) -> Void = { _ in }
    /// Presents a screen over or beside the window, which moves nothing in it.
    public var present: (Presentation) -> Void = { _ in }
    /// A message window's conversation went, so the window goes once that can't be undone.
    public var leaveWindow: () -> Void = {}
    /// Clears what covers the window for an arrival from outside, then calls `then`, once, when it is clear. The
    /// effects after it wait for it, so a lookup answers over a window already uncovered.
    public var uncover: (_ then: @escaping () -> Void) -> Void = { $0() }
    /// Tells the reader something the window can't show.
    public var say: (WindowNavigation.Notice) -> Void = { _ in }

    public init(
        showing state: WindowState, checking lists: WindowState.ListCheck,
        context: @escaping () -> WindowNavigation.Context, lookUp: @escaping LookUp
    ) {
        navigation = WindowNavigation(showing: state, checking: lists)
        self.context = context
        self.lookUp = lookUp
    }

    isolated deinit {
        arriving?.cancel()
    }

    /// What the window shows.
    public var state: WindowState { navigation.state }

    /// Shows the viewer in `split`, with new screens made by `makers`, in the place of any shown before.
    public func show(in split: MailSplitViewController, making makers: MailScreens.Makers) {
        let screens = MailScreens(
            state, row: navigation.foundRow, in: split, arrangement: context().arrangement, making: makers)
        screens.wentBack = { [weak self] in self?.send(.back(to: $0)) }
        self.screens = screens
        if !screens.readable { readerUnmade() }
    }

    /// The window no longer shows the viewer's screens, as before it is rebuilt or while it shows one conversation.
    public func leaveScreens() {
        screens = nil
    }

    /// The window changed width: the arrangement it shows now catches up.
    public func arrangementChanged() {
        guard let screens else { return }
        if !screens.show(state, row: navigation.foundRow, .resized, in: context().arrangement) { readerUnmade() }
    }

    /// Moves the window for `event`.
    public func send(_ event: WindowNavigation.Event) {
        let before = state
        let context = context()
        let effects = navigation.handle(event, in: context)
        if navigation.pending == nil {
            arriving?.cancel()
            arriving = nil
        }
        if state != before {
            let showing: MailScreens.Showing = event.movesByItself ? .announced : .quiet
            if let screens, !screens.show(state, row: navigation.foundRow, showing, in: context.arrangement) {
                readerUnmade()
            }
            stateChanged(state)
        }
        perform(effects[...])
    }

    /// The reader for what is read couldn't be made, as for a conversation whose account just went: it is gone.
    private func readerUnmade() {
        guard let thread = state.reading?.thread else { return }
        send(.missing(thread))
    }

    /// Performs `effects` in order. Those after `.uncover` wait until the window is clear.
    private func perform(_ effects: ArraySlice<WindowNavigation.Effect>) {
        guard let effect = effects.first else { return }
        let rest = effects.dropFirst()
        guard effect != .uncover else {
            return uncover { [weak self] in self?.perform(rest) }
        }
        perform(effect)
        perform(rest)
    }

    private func perform(_ effect: WindowNavigation.Effect) {
        switch effect {
        case .uncover:
            // Performed in order above, as the effects after it wait for it.
            break
        case .lookUp(let thread):
            find(thread)
        case .present(let presentation):
            present(presentation)
        case .beginSearch(let query):
            screens?.whenSettled { [weak self] in (self?.screens?.list as? MailboxViewController)?.beginSearch(query) }
        case .showList:
            screens?.split.showList()
        case .showPicked(let count):
            screens?.showPicked(count)
        case .leaveWindow:
            leaveWindow()
        case .say(let notice):
            say(notice)
        }
    }

    /// Finds `thread`: at once from the list on show when it holds it, else from the store. A lookup the navigation
    /// stopped waiting for while the window was being uncovered isn't started.
    private func find(_ thread: ThreadSummary.ID) {
        guard navigation.pending?.reading.thread == thread else { return }
        arriving?.cancel()
        arriving = nil
        if let front = screens?.front, let row = front.summary(of: thread) {
            return send(.found(row, rows: front.frontRows))
        }
        arriving = Task { @concurrent [weak self, lookUp] in
            let row = await lookUp(thread)
            await self?.arrived(row, as: thread)
        }
    }

    /// The store's answer for `thread`, unless the navigation stopped waiting for it. Called on the lookup's own task,
    /// which only the main actor cancels, so the check and what follows can't be split by a newer lookup.
    private func arrived(_ row: ThreadSummary?, as thread: ThreadSummary.ID) {
        guard !Task.isCancelled else { return }
        arriving = nil
        guard let row else { return send(.missing(thread)) }
        send(.found(row, rows: screens?.front?.frontRows ?? []))
    }
}
