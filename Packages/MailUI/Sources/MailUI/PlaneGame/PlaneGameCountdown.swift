import PlaneGame
import SwiftUI

/// The countdown before a paused game carries on: 3, 2 and 1 in the middle of the field, each in a doodle ring that
/// undraws over its second. Each number pops in and fades at the end of its second; with Reduce Motion on the numbers
/// only fade and the ring stays whole. It is drawn from the model's hold every frame, so it never runs apart from it.
struct PlaneGameCountdown: View {
    /// Seconds until the game moves again.
    let left: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        let beat = PlaneGameCountdownBeat(left: left, reduceMotion: reduceMotion)
        ZStack {
            Circle()
                .trim(from: 0, to: beat.ring)
                .stroke(DoodlePalette.purple.opacity(0.5), style: DoodleField.line)
                .rotationEffect(.degrees(-90))
                .frame(width: 128, height: 128)
            Text(verbatim: beat.count.formatted(.number))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DoodlePalette.purple)
                .scaleEffect(beat.scale)
                .opacity(beat.opacity)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                "Resuming in \(beat.count)", tableName: "PlaneGame", bundle: .module,
                comment: "The countdown before a paused paper plane game carries on, read by VoiceOver")
        )
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// How the countdown looks `left` seconds before the game moves again.
nonisolated struct PlaneGameCountdownBeat: Equatable {
    /// The number that shows: 3, 2 then 1.
    let count: Int
    let scale: Double
    let opacity: Double
    /// How much of the ring is still drawn.
    let ring: Double

    /// How long a number takes to pop in, and to fade at the end of its second.
    static let popIn: TimeInterval = 0.25
    static let fadeOut: TimeInterval = 0.2

    init(left: TimeInterval, reduceMotion: Bool) {
        count = PlaneGameHold.countingDown(left: left).count ?? 1
        // How far into its own second the number is, from 0 to 1.
        let into = min(max(Double(count) - left, 0), 1)
        let fadesIn = PlaneGameEasing.ramp(into, from: 0, to: reduceMotion ? Self.fadeOut : Self.popIn)
        opacity = fadesIn * (1 - PlaneGameEasing.ramp(into, from: 1 - Self.fadeOut, to: 1))
        scale = reduceMotion ? 1 : 1.4 - 0.4 * PlaneGameEasing.easeOut(fadesIn)
        ring = reduceMotion ? 1 : 1 - into
    }
}
