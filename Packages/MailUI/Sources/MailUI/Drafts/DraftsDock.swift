import MailCore
import UIKit

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
/// card setting off over it, and `updateProperties()` runs later.
public final class DraftsDock {
    /// The messages minimized. Only `show` changes it.
    private var shelved = Shelved.none
    /// Whether a card is on its way into the pill, which counts its message from the moment it sets off. The shelf's
    /// count and the stage's card are independent facts: every combination is valid.
    private var isReceiving = false
    /// A pill was tapped.
    var onOpen: (() -> Void)?
    /// Dismiss All was picked in a pill's menu, the pill being the view to anchor what it asks.
    var onDismissAll: ((UIView) -> Void)?
    private var pills: [WeakPill] = []

    private struct WeakPill {
        weak var pill: DraftsPillItem?
    }

    init() {}

    /// A pill for `site`'s toolbar, showing the count now and from now on.
    func makePill(for site: any DraftsPillSite) -> DraftsPillItem {
        let pill = DraftsPillItem(
            site: site, opened: { [weak self] in self?.onOpen?() },
            dismissAll: { [weak self] in self?.onDismissAll?($0) })
        pills.removeAll { $0.pill == nil }
        pills.append(WeakPill(pill: pill))
        render(pill)
        return pill
    }

    /// Shows how many of `minimized` there are on every pill, and the title of a lone one; none hides them.
    func show(_ minimized: [Draft]) {
        shelved = Shelved(minimized)
        render()
    }

    /// A card sets off for the pill on show: every pill counts its message from now, while the open card still covers
    /// it, and this says where to aim in `view`. `nil`, counting nothing, when no pill is on show or placed. A
    /// reception ends with `land` once the card is in, or `turnAway` if it never gets there.
    func receive(in view: UIView) -> PillSpot? {
        guard shownPill != nil else { return nil }
        expect()
        guard let spot = spot(in: view) else {
            turnAway()
            return nil
        }
        return spot
    }

    /// Every pill counts a card on its way in, from now.
    func expect() {
        isReceiving = true
        render()
    }

    /// The card came back: the pills stop counting its message.
    func turnAway() {
        guard isReceiving else { return }
        isReceiving = false
        render()
    }

    /// The card is in: `docked` marks its message minimized, and the pills go on showing what they showed.
    func land(_ docked: () -> Void) {
        isReceiving = false
        docked()
        render()
    }

    /// The pill whose place is on screen now, shown or hidden.
    var shownPill: DraftsPillItem? {
        pills.lazy.compactMap(\.pill).first(where: \.isOnShow)
    }

    /// Where the pill on show is in `view` as it shows now; `nil` when none is on show or the toolbar hasn't placed it.
    func spot(in view: UIView) -> PillSpot? {
        shownPill?.spot(in: view)
    }

    private func render() {
        for box in pills { box.pill.map(render) }
    }

    private func render(_ pill: DraftsPillItem) {
        // A card on its way in is a message of its own, without a title the pill would read out.
        if isReceiving { return pill.show(shelved.count + 1) }
        switch shelved {
        case .none: pill.show(0)
        case .one(let title): pill.show(1, title: title)
        case .several(let count): pill.show(count)
        }
    }
}

/// The messages minimized, as the pills tell them: how many, and what a lone one is called.
private enum Shelved: Equatable {
    case none
    case one(title: String)
    case several(Int)

    init(_ minimized: [Draft]) {
        switch minimized.count {
        case 0: self = .none
        case 1: self = .one(title: minimized[0].shelfTitle)
        case let count: self = .several(count)
        }
    }

    var count: Int {
        switch self {
        case .none: 0
        case .one: 1
        case .several(let count): count
        }
    }
}
