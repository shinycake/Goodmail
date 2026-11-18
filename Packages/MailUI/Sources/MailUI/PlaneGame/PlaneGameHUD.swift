import PlaneGame
import SwiftUI

/// The game's top bar: the lives on the leading side, the score in the middle and on the trailing side the pause and
/// the way out, two doodles quiet enough to read as more of the backdrop until they are looked for, with mail that
/// arrived during the game just inside them.
struct PlaneGameHUD: View {
    let lives: Int
    let score: Int
    let mailWaiting: Int
    let mailArrivals: Int
    let pause: () -> Void
    let exit: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            Button(action: pause) {
                PauseBars()
                    .stroke(washed[PlaneGameArt.pink], style: DoodleField.line)
                    .frame(width: 10, height: 13)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text("Pause", tableName: "PlaneGame", bundle: .module, comment: "Pauses the paper plane game"))
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
        .padding(.horizontal, horizontalSizeClass == .regular ? 20 : 12)
        // Narrowed to keep clear of an iPad window's own controls, which stay in its top left corner in either
        // direction, so they sit beside the lives, or beside the way out in a right-to-left layout.
        .containerCornerOffset(.horizontal, sizeToFit: true)
    }
}

/// The pause sign as a doodle: two upright strokes.
nonisolated private struct PauseBars: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in [rect.minX, rect.maxX] {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}
