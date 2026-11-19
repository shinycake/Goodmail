import PlaneGame
import SwiftUI

/// How the boss's title looks `age` seconds after the boss started to slide in: it fades in, settling from a little
/// larger, stays, and fades out before the first attack. With Reduce Motion on it only fades.
nonisolated struct PlaneGameBossTitleBeat: Equatable, Sendable {
    let opacity: Double
    let scale: Double

    static let fadeIn: TimeInterval = 0.25
    static let staysFor: TimeInterval = 1.6
    static let fadeOut: TimeInterval = 0.4

    init(age: TimeInterval, reduceMotion: Bool) {
        let shown = PlaneGameEasing.ramp(age, from: 0, to: Self.fadeIn)
        opacity = shown * (1 - PlaneGameEasing.ramp(age, from: Self.staysFor, to: Self.staysFor + Self.fadeOut))
        scale = reduceMotion ? 1 : 1.25 - 0.25 * PlaneGameEasing.easeOut(shown)
    }
}

/// The round and the boss's name, over the middle of the field as the boss slides in. VoiceOver hears them as an
/// announcement instead. It is in the screen only while it shows.
struct PlaneGameBossTitle: View {
    let kind: PlaneGameBoss.Kind
    let round: Int
    let center: CGPoint
    /// The widest it may be: the lanes.
    let width: CGFloat
    let beat: PlaneGameBossTitleBeat

    var body: some View {
        VStack(spacing: 2) {
            PlaneGameRoundLabel(round: round, font: .subheadline.weight(.semibold))
            Text(verbatim: PlaneGameBossName.of(kind))
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(DoodlePalette.pink)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(maxWidth: width)
        .scaleEffect(beat.scale)
        .opacity(beat.opacity)
        .position(center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where it sits for `boss` on `field`: a little under halfway down, and well clear of the bottom of the boss's
    /// drawing, whatever hangs from it.
    static func center(for boss: PlaneGameBoss, on field: PlaneGameField) -> CGPoint {
        let artBottom = field.ceiling + boss.headroom + 0.75 * PlaneGameArt.size(of: boss.kind)
        return CGPoint(
            x: field.startingPlace.x, y: max(field.ceiling + 0.45 * (field.row - field.ceiling), artBottom + 48))
    }
}
