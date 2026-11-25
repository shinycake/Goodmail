/// Where a message view's body is: the content it shows or is on its way to showing, and whether the page in the web
/// view is that content's. Only a committed page's script reports count: the page before it, as the body before Load
/// Remote Images or a spare's blank one, can still report while its replacement loads, about content no longer shown.
nonisolated enum BodyLoad<Content: Equatable, Navigation: AnyObject> {
    /// The content on its way and what the view knows of its body.
    struct Shown {
        var content: Content
        /// The body that shows has a height for this message, so its words no longer stand in for it. Loading the same
        /// message again, as with its remote images, keeps the body that shows and so its height.
        var sized: Bool
        /// When the load last failed or its page went and it was started again, `nil` if never. Another failure within
        /// `reloadQuiet` of it leaves the body as it is, so a page that always fails, or always loses its process once
        /// it lays out, can't reload forever; a page lost once in a while still comes back.
        var lastReload: ContinuousClock.Instant?

        func reloads(at now: ContinuousClock.Instant) -> Bool {
            lastReload.map { now - $0 >= reloadQuiet } ?? true
        }
    }

    /// How long after a reload another failure is taken as the page failing for good.
    static var reloadQuiet: Duration { .seconds(60) }

    /// A spare's blank page, before any message.
    case blank
    /// Building the content's document, which `work` then loads.
    case preparing(Shown, work: Task<Void, Never>)
    /// Loading the content's page.
    case navigating(Shown, Navigation)
    /// The content's page is in, and its script's reports count.
    case committed(Shown, Navigation)

    private var shown: Shown? {
        switch self {
        case .blank: nil
        case .preparing(let shown, _), .navigating(let shown, _), .committed(let shown, _): shown
        }
    }

    var content: Content? { shown?.content }

    /// The content whose page reports now, or `nil` while none does.
    var reporting: Content? {
        guard case .committed(let shown, _) = self else { return nil }
        return shown.content
    }

    /// Whether the message's words stand in for a body that has no height yet.
    var showsPreview: Bool { shown.map { !$0.sized } ?? false }

    /// Starts on `content`, which `work` prepares, replacing whatever was under way. `sameMessage` keeps the height of
    /// the body that shows.
    mutating func show(_ content: Content, sameMessage: Bool, work: Task<Void, Never>) {
        cancel()
        let sized = sameMessage && shown?.sized == true
        self = .preparing(Shown(content: content, sized: sized, lastReload: nil), work: work)
    }

    /// The content to load again, at `now`, when its load failed or its page went, or `nil` when there is none, it was
    /// loaded again too recently, or it is still being prepared and so loads anyway.
    func reloadable(at now: ContinuousClock.Instant) -> Content? {
        switch self {
        case .navigating(let shown, _) where shown.reloads(at: now),
            .committed(let shown, _) where shown.reloads(at: now):
            shown.content
        case .blank, .preparing, .navigating, .committed: nil
        }
    }

    /// Loads the content shown again with `work` at `now`, when it may (`reloadable(at:)`).
    mutating func reload(work: Task<Void, Never>, at now: ContinuousClock.Instant) {
        switch self {
        case .navigating(var shown, _) where shown.reloads(at: now),
            .committed(var shown, _) where shown.reloads(at: now):
            shown.lastReload = now
            self = .preparing(shown, work: work)
        case .blank, .preparing, .navigating, .committed:
            work.cancel()
        }
    }

    /// The prepared document started loading as `navigation`.
    mutating func load(_ navigation: Navigation) {
        guard case .preparing(let shown, _) = self else { return }
        self = .navigating(shown, navigation)
    }

    /// Whether the view waits for `navigation` to commit.
    func awaits(_ navigation: Navigation) -> Bool {
        guard case .navigating(_, let loading) = self else { return false }
        return loading === navigation
    }

    /// `navigation` committed its page; one the view no longer waits for changes nothing.
    mutating func commit(_ navigation: Navigation) {
        guard case .navigating(let shown, let loading) = self, loading === navigation else { return }
        self = .committed(shown, navigation)
    }

    /// The committed page reported its height: the content it is for, or `nil` when no page reports now.
    mutating func laidOut() -> Content? {
        guard case .committed(var shown, let navigation) = self else { return nil }
        shown.sized = true
        self = .committed(shown, navigation)
        return shown.content
    }

    /// Stops the preparing that is under way, as the view goes or another load replaces it.
    func cancel() {
        if case .preparing(_, let work) = self { work.cancel() }
    }
}
