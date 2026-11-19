import MailCore

/// A screen whose bottom toolbar holds the drafts pill. The mail list is one; any screen with a toolbar can be,
/// by conforming and putting `DraftsDock.makePill(for:)`'s item in its toolbar.
protocol DraftsPillSite: AnyObject {
    /// Whether the pill's place is on screen and still: the screen in a window, on top of its stack, browsing, not
    /// searching, its toolbar showing, and no push or pop under way.
    var showsDraftsPill: Bool { get }
    /// The pill was shown, hidden or resized: lays the toolbar out now, and lets the undo toast find its room again.
    func draftsPillDidChange()
}

/// One per window: tells every pill how many messages are minimized, and hears a pill tapped.
///
/// A hub rather than Observation, because the count must reach the pill in the same run-loop turn as the composer's
/// chip covering it, and `updateProperties()` runs later.
public final class DraftsDock {
    /// How many messages are minimized. Only `show` changes it.
    private(set) var count = 0
    /// What the only minimized message is called; `nil` unless there is exactly one.
    private var title: String?
    /// A pill was tapped.
    var onOpen: (() -> Void)?
    private var pills: [WeakPill] = []

    private struct WeakPill {
        weak var pill: DraftsPillItem?
    }

    init() {}

    /// A pill for `site`'s toolbar, showing the count now and from now on.
    func makePill(for site: any DraftsPillSite) -> DraftsPillItem {
        let pill = DraftsPillItem(site: site) { [weak self] in self?.onOpen?() }
        pills.removeAll { $0.pill == nil }
        pills.append(WeakPill(pill: pill))
        pill.show(count, title: title)
        return pill
    }

    /// Shows how many of `minimized` there are on every pill, and the title of a lone one; none hides them.
    func show(_ minimized: [Draft]) {
        count = minimized.count
        title = minimized.count == 1 ? minimized[0].shelfTitle : nil
        for box in pills { box.pill?.show(count, title: title) }
    }

    /// The pill whose place is on screen now, shown or hidden.
    var shownPill: DraftsPillItem? {
        pills.lazy.compactMap(\.pill).first(where: \.isOnShow)
    }
}
