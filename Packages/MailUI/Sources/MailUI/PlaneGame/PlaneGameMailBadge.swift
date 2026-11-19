import SwiftUI

/// Mail that arrived during the game, in the HUD's corner: a purple envelope doodle that draws itself in with the
/// count beside it, hops once on each arrival and undraws if the mail goes away. The app shows no banner while it is
/// open and the game covers the list, so this says it, without pausing anything or covering the field. It is a way
/// out: to the list, where the mail is, once the reader confirms leaving the game.
struct PlaneGameMailBadge: View {
    /// Threads waiting in the Inbox.
    let count: Int
    /// Counts the arrivals, each of which hops the envelope.
    let arrivals: Int
    let leave: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = count > 0
        // Read here: the hop's closure is called off the main actor.
        let hops = !reduceMotion
        Button(action: leave) {
            HStack(spacing: 4) {
                DoodleOutline(shape: .envelope)
                    // Drawn in like a doodle being sketched, or with Reduce Motion on, faded in.
                    .trim(from: 0, to: shown || reduceMotion ? 1 : 0)
                    .stroke(DoodlePalette.purple, style: DoodleField.line)
                    .frame(width: 18, height: 18)
                    // The list's unread dot on its corner, so it reads as mail and not as a fourth life.
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(DoodlePalette.purple)
                            .padding(1.5)
                            .background(Color(uiColor: .systemBackground), in: .circle)
                            .frame(width: 9, height: 9)
                            .offset(x: 3, y: -1)
                            .scaleEffect(shown || reduceMotion ? 1 : 0.01)
                    }
                    .opacity(shown || !reduceMotion ? 1 : 0)
                // Never 0, which would fade out under the first count as it fades in. Later counts roll in.
                Text(verbatim: max(count, 1).formatted(.number))
                    .font(.footnote.bold())
                    .monospacedDigit()
                    .foregroundStyle(DoodlePalette.purple)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy, value: count)
                    .opacity(shown ? 1 : 0)
            }
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: arrivals) { content, lift in
                content.offset(y: hops ? -lift : 0)
            } keyframes: { _ in
                SpringKeyframe(6, duration: 0.14, spring: .snappy)
                SpringKeyframe(0, duration: 0.4, spring: .bouncy)
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.5), value: shown)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .accessibilityLabel(Self.label)
        .accessibilityValue(Text(verbatim: count.formatted(.number)))
        .accessibilityHint(
            Text("Back to Inbox", tableName: "PlaneGame", bundle: .module, comment: "Leaves the paper plane game")
        )
        .sensoryFeedback(.impact(flexibility: .soft), trigger: arrivals)
        .onChange(of: shown) { _, appeared in
            if appeared {
                SystemAccessibility.announce(
                    String(
                        localized: "New Mail", table: "PlaneGame", bundle: .module,
                        comment:
                            "Mail arrived during the paper plane game: the HUD's envelope, and what VoiceOver says when it shows"
                    ))
            }
        }
    }

    private static var label: Text {
        Text(
            "New Mail", tableName: "PlaneGame", bundle: .module,
            comment:
                "Mail arrived during the paper plane game: the HUD's envelope, and what VoiceOver says when it shows")
    }
}
