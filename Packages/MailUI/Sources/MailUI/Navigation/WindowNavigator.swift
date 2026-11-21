public import MailCore

/// Runs one window's navigation (`WindowNavigation`): every event goes through `send(_:)`, which moves the state,
/// has the screens show it (`MailScreens`), and does what the transition says beyond that. A conversation to open is
/// found in the list on show when it holds it, else in the store or from its service, off the main actor
/// (`ConversationLookup`). The navigation says which lookup it waits for (`pending`); one it no longer waits for is
/// cancelled.
///
/// Effects that need the window wait for it (`Deferred`): those after `.uncover` until the window is clear, and those
/// that present or touch the screens until the window is on screen, as at a cold launch. Each route that comes
/// meanwhile replaces what waits, so only the newest arrival's screen comes up.
public final class WindowNavigator {
    /// Finds a conversation's row, off the main actor.
    public typealias LookUp = @concurrent @Sendable (ThreadSummary.ID) async -> ConversationLookup.Answer
    /// Reads a conversation's row from the store alone, off the main actor; `nil` when it isn't on the device.
    public typealias Stored = @concurrent @Sendable (ThreadSummary.ID) async -> ThreadSummary?

    /// Effects waiting for the window.
    private enum Deferred: Equatable {
        case none
        /// The window is being uncovered for an arrival; these follow once it is clear. Another arrival meanwhile
        /// replaces them rather than uncover again, which would lose the dismissal under way.
        case uncovering(then: ArraySlice<WindowNavigation.Effect>)
        /// The window isn't on screen yet, as at a cold launch, or before its screens are built; these follow once it
        /// is.
        case waitingForScreen(ArraySlice<WindowNavigation.Effect>)
    }

    public private(set) var navigation: WindowNavigation
    /// The viewer's screens; `nil` while the window shows something else, as one conversation alone.
    public private(set) var screens: MailScreens?
    private let lookUp: LookUp
    private let stored: Stored
    /// The store read under way for the conversation read, before the screens are built for it (`rebuild`).
    private var confirming: Task<Void, Never>?
    /// What the window knows now apart from what it shows: how it lays it out, from its width class, which holds
    /// before it is on screen, and the setting read at each change.
    private let context: () -> WindowNavigation.Context
    /// The store lookup under way, for `navigation.pending`.
    private var arriving: Task<Void, Never>?
    private var deferred = Deferred.none
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
    /// Whether the window is on screen in an active scene, so a sheet presented over it shows.
    public var isOnScreen: () -> Bool = { true }

    public init(
        showing state: WindowState, checking lists: WindowState.ListCheck,
        context: @escaping () -> WindowNavigation.Context, lookUp: @escaping LookUp, stored: @escaping Stored
    ) {
        navigation = WindowNavigation(showing: state, checking: lists)
        self.context = context
        self.lookUp = lookUp
        self.stored = stored
    }

    isolated deinit {
        arriving?.cancel()
        confirming?.cancel()
    }

    /// Leaves the screens for new ones for `accounts`, then calls `build` once the conversation read, if any, is known
    /// to be on the device, with its row for the reader, read off the main actor unless the screens on show had it.
    /// One gone closes first. A newer rebuild replaces one waiting.
    public func rebuild(for accounts: [AccountID], then build: @escaping () -> Void) {
        let thread = state.reading?.thread
        let known = thread.flatMap { thread in
            screens?.reader.map(\.conversation).flatMap { $0.id == thread ? $0 : nil }
                ?? screens?.front?.summary(of: thread)
        }
        confirming?.cancel()
        confirming = nil
        leaveScreens()
        send(.accounts(accounts))
        if let known { send(.restored(known)) }
        guard let thread = state.reading?.thread, navigation.foundRow?.id != thread else { return build() }
        confirming = Task { [weak self, stored] in
            let row = await stored(thread)
            guard !Task.isCancelled, let self else { return }
            confirming = nil
            if state.reading?.thread == thread { send(row.map(WindowNavigation.Event.restored) ?? .missing(thread)) }
            build()
        }
    }

    /// What the window shows.
    public var state: WindowState { navigation.state }

    /// Shows the viewer in `split`, with new screens made by `makers`, in the place of any shown before.
    public func show(in split: MailSplitViewController, making makers: MailScreens.Makers) {
        let steps = ConversationSteps(
            leads: { [weak self] in self?.leads($0) == true }, take: { [weak self] in self?.take($0) })
        split.steps = steps
        let screens = MailScreens(
            state, row: navigation.foundRow, in: split, arrangement: context().arrangement, steps: steps,
            making: makers)
        screens.wentBack = { [weak self] in self?.send(.back(to: $0)) }
        self.screens = screens
        if !screens.readable { readerUnmade() }
        cameOnScreen()
    }

    /// The window came on screen, or may have: what waited for it follows.
    public func cameOnScreen() {
        guard case .waitingForScreen(let waiting) = deferred, isOnScreen() else { return }
        deferred = .none
        perform(waiting)
    }

    /// The window no longer shows the viewer's screens, as before it is rebuilt or while it shows one conversation.
    public func leaveScreens() {
        screens = nil
    }

    /// The window changed width, or is about to, to `arrangement`: the list and the reader move there (D8).
    public func arrangementChanged(to arrangement: WindowNavigation.Arrangement) {
        guard let screens else { return }
        if !screens.show(state, row: navigation.foundRow, .resized, in: arrangement) { readerUnmade() }
    }

    /// Moves the window for `event`.
    public func send(_ event: WindowNavigation.Event) {
        let before = state
        let context = context()
        switch event {
        case .route, .launched: dropWaitingEffects()
        default: break
        }
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

    /// Whether Next or Previous Conversation leads anywhere from what is read, in the list on show.
    private func leads(_ step: WindowNavigation.Step) -> Bool {
        navigation.conversation(step, in: screens?.front?.navigationFront) != nil
    }

    /// Next or Previous Conversation, through the list on show.
    private func take(_ step: WindowNavigation.Step) {
        send(.step(step, front: screens?.front?.navigationFront))
    }

    /// The reader for what is read couldn't be made, as for a conversation whose account just went: it is gone.
    private func readerUnmade() {
        guard let thread = state.reading?.thread else { return }
        send(.missing(thread))
    }

    /// A newer route replaces what an earlier one left waiting. An uncovering under way goes on, for the newer one.
    private func dropWaitingEffects() {
        switch deferred {
        case .none: break
        case .uncovering: deferred = .uncovering(then: [])
        case .waitingForScreen: deferred = .none
        }
    }

    /// Performs `effects` in order, those that need the window once it can take them (`Deferred`).
    private func perform(_ effects: ArraySlice<WindowNavigation.Effect>) {
        guard let effect = effects.first else { return }
        let rest = effects.dropFirst()
        if effect == .uncover {
            return beginUncovering(then: effects)
        }
        guard canPerform(effect) else { return wait(effects) }
        perform(effect)
        perform(rest)
    }

    /// Uncovers the window for `effects`, which start with `.uncover`, then performs the rest; joins an uncovering
    /// under way rather than start another.
    private func beginUncovering(then effects: ArraySlice<WindowNavigation.Effect>) {
        let rest = effects.dropFirst()
        switch deferred {
        case .uncovering:
            deferred = .uncovering(then: rest)
        case .none, .waitingForScreen:
            // A window off screen is uncovered once it is on screen.
            guard isOnScreen() else {
                deferred = .waitingForScreen(effects)
                return
            }
            deferred = .uncovering(then: rest)
            uncover { [weak self] in self?.uncovered() }
        }
    }

    /// The window is clear: what waited for it follows.
    private func uncovered() {
        guard case .uncovering(let waiting) = deferred else { return }
        deferred = .none
        perform(waiting)
    }

    /// `effects` wait for the window to come on screen, after any uncovering under way.
    private func wait(_ effects: ArraySlice<WindowNavigation.Effect>) {
        switch deferred {
        case .uncovering(let waiting): deferred = .uncovering(then: waiting + effects)
        case .none, .waitingForScreen: deferred = .waitingForScreen(effects)
        }
    }

    /// Whether `effect` can be performed now: a screen presented needs the window on screen, and what touches the
    /// screens or the toast needs them built too.
    private func canPerform(_ effect: WindowNavigation.Effect) -> Bool {
        switch effect {
        case .uncover, .lookUp, .leaveWindow: true
        case .present: isOnScreen()
        case .beginSearch, .showList, .showPicked, .say: screens != nil && isOnScreen()
        }
    }

    private func perform(_ effect: WindowNavigation.Effect) {
        switch effect {
        case .uncover:
            // Begun in order above, as the effects after it wait for it.
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
            let answer = await lookUp(thread)
            await self?.arrived(answer, for: thread)
        }
    }

    /// The lookup's answer for `thread`, unless the navigation stopped waiting for it. Called on the lookup's own task,
    /// which only the main actor cancels, so the check and what follows can't be split by a newer lookup.
    private func arrived(_ answer: ConversationLookup.Answer, for thread: ThreadSummary.ID) {
        guard !Task.isCancelled else { return }
        arriving = nil
        switch answer {
        case .found(let row): send(.found(row, rows: screens?.front?.frontRows ?? []))
        case .gone: send(.missing(thread))
        case .unreachable: send(.unreachable(thread))
        }
    }
}
