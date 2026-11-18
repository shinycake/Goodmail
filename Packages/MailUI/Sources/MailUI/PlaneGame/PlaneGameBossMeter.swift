import PlaneGame
import SwiftUI

/// The boss's hits left, as a pink line on a washed track under the score. It draws itself in from the leading
/// side as the boss slides in and shortens toward it with each hit, so it reads the same way in a right-to-left
/// layout. It sits in the middle, clear of the lives, the mail and the way out.
struct PlaneGameBossMeter: View {
    let line: PlaneGameBossLine
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let track = PlaneGameBossLine.width * line.drawn
        ZStack(alignment: .leading) {
            Capsule()
                .fill(DoodleField.inks(for: colorScheme)[PlaneGameArt.pink])
                .frame(width: track)
            Capsule()
                .fill(DoodlePalette.pink)
                .frame(width: track * line.left)
        }
        .frame(width: PlaneGameBossLine.width, height: 4, alignment: .leading)
        .opacity(line.opacity)
        .padding(.top, 2)
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityValue(
            Text(
                "\(line.hitsLeft) hits left", tableName: "PlaneGame", bundle: .module,
                comment: "How many hits the boss in the paper plane game can still take, read by VoiceOver"))
    }

    private var name: Text {
        switch line.kind {
        case .junk:
            Text(
                "Junk Mail", tableName: "PlaneGame", bundle: .module,
                comment: "A boss in the paper plane game: a spam envelope wearing a crown")
        case .phisher:
            Text(
                "The Phisher", tableName: "PlaneGame", bundle: .module,
                comment: "A boss in the paper plane game: an at sign that casts hooks")
        }
    }
}
