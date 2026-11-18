import PlaneGame
import SwiftUI

/// The game's top bar: the lives on the leading side, the score in the middle and the way out on the trailing side,
/// a cross doodle quiet enough to read as one more doodle until it is looked for, with mail that arrived during the
/// game just inside it.
struct PlaneGameHUD: View {
    let lives: Int
    let score: Int
    let mailWaiting: Int
    let mailArrivals: Int
    let exit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let washed = DoodleField.inks(for: colorScheme)
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<PlaneGameRules.lives, id: \.self) { life in
                    DoodleOutline(shape: .envelope)
                        .stroke(
                            life < lives ? DoodlePalette.purple : washed[PlaneGameArt.purple],
                            style: DoodleField.line
                        )
                        .frame(width: 16, height: 16)
                }
            }
            .accessibilityHidden(true)
            Spacer()
            PlaneGameMailBadge(count: mailWaiting, arrivals: mailArrivals, exit: exit)
            Button(action: exit) {
                DoodleOutline(shape: .cross)
                    .stroke(washed[PlaneGameArt.pink], style: DoodleField.line)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(45))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text("Back to Inbox", tableName: "PlaneGame", bundle: .module, comment: "Leaves the paper plane game"))
        }
        .overlay {
            Text(score, format: .number)
                .font(.title3.bold())
                .monospacedDigit()
                .accessibilityLabel(Text("Score", tableName: "PlaneGame", bundle: .module, comment: "The game's score"))
                .accessibilityValue(
                    Text(
                        "\(score) points", tableName: "PlaneGame", bundle: .module,
                        comment: "The paper plane game's score, read by VoiceOver"))
        }
        .padding(.horizontal, 12)
    }
}
