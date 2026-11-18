import SwiftUI

/// Where the pane beside the list is, and the window's sky, whose empty Inbox the pane carries on.
@Observable final class NoThreadPane {
    /// The window's sky, once the pane is in a window.
    var sky: InboxZeroSky?
    /// The pane, in the window's coordinates.
    var frame = CGRect.zero
    /// The space its doodles spread over, inside its safe area, in the window's coordinates.
    var field = CGRect.zero
}

/// The pane beside the list while no thread is open. Beside an empty Inbox with room for doodles nothing can be
/// selected, so instead of saying so it carries the scene on: its doodles spill over the line between the list and the
/// pane, drift with the ring, are pushed aside by touches anywhere in the window, and a tap here sends a plane off from
/// under the finger. Where the scene has no doodles, as at accessibility text sizes, it says "No Message Selected" as
/// usual, and while the paper plane game covers the window it is left empty.
struct NoThreadView: View {
    let pane: NoThreadPane
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let inbox = pane.sky?.inbox
        let reach = inbox?.reach
        ZStack {
            if let inbox, let reach {
                // Measured in the window's coordinates, which run from the left whatever the language.
                InboxZeroBeyond(
                    reach: reach, poke: inbox.poke, pane: pane, rightToLeft: layoutDirection == .rightToLeft
                )
                .environment(\.layoutDirection, .leftToRight)
                .transition(.opacity)
            } else if inbox?.isPlaying != true {
                ContentUnavailableView {
                    Label {
                        Text(
                            "No Message Selected", tableName: "Thread", bundle: .module,
                            comment: "Shown beside the list on iPad while no thread is open")
                    } icon: {
                        Image(systemName: "envelope")
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.25), value: reach == nil)
    }
}

/// The Inbox Zero scene's doodles carried on across the pane beside the list. Measured in the pane's own space, the
/// envelopes are off to one side, beyond the pane's edge, so a touch on the scene pushes these doodles too and the
/// ring's drawing-in ripples on across them.
private struct InboxZeroBeyond: View {
    let reach: InboxZeroReach
    /// Lands a touch on the scene, measured from the middle of the envelopes.
    let poke: (CGSize) -> Void
    let pane: NoThreadPane
    let rightToLeft: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || reach.wake == .asleep)) { timeline in
            frame(at: timeline.date)
        }
        .ignoresSafeArea()
    }

    private func frame(at now: Date) -> some View {
        let field = pane.field
        let stage = reach.stage
        let entrance = InboxZeroEntrance(
            arrival: reach.showing.arrival,
            elapsed: reduceMotion ? nil : now.timeIntervalSince(reach.showing.arrivedAt))
        // The envelopes, from the field's corner.
        let focus = CGPoint(x: stage.center.x - field.minX, y: stage.center.y - field.minY)
        let scene = DoodleScene(
            size: field.size, pokes: reach.pokes.live, clock: reduceMotion ? .stopped : .running(now),
            rightToLeft: rightToLeft, focus: focus, energy: reach.wake.energy(at: now),
            widest: .infinity)
        let farthest =
            [
                CGPoint.zero, CGPoint(x: field.width, y: 0), CGPoint(x: 0, y: field.height),
                CGPoint(x: field.width, y: field.height),
            ]
            .map { hypot($0.x - focus.x, $0.y - focus.y) }.max() ?? 0
        return DoodleField(
            doodles: Doodle.inboxZeroBeyond, scene: scene, reveal: entrance.revealBeyond(from: focus, reach: farthest)
        )
        .frame(width: field.width, height: field.height)
        .position(x: field.midX - pane.frame.minX, y: field.midY - pane.frame.minY)
        .opacity(entrance.opacity)
        .contentShape(.rect)
        .onTapGesture { location in
            guard !reduceMotion else { return }
            // From the pane's corner to the window's, then from the envelopes.
            poke(
                CGSize(
                    width: pane.frame.minX + location.x - stage.center.x,
                    height: pane.frame.minY + location.y - stage.center.y))
        }
        .accessibilityHidden(true)
    }
}
