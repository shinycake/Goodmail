import SwiftUI

/// The card a game ends on: the score, the best score, and the choice of another go or the way back.
struct PlaneGameOverCard: View {
    let result: PlaneGameResult
    let playAgain: () -> Void
    let exit: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Returned to Sender", tableName: "PlaneGame", bundle: .module, comment: "Title of the game over card")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 36) {
                figure(
                    Text("Score", tableName: "PlaneGame", bundle: .module, comment: "The game's score"),
                    value: result.score)
                figure(best, value: result.best)
                    .foregroundStyle(result.isNewBest ? DoodlePalette.purple : Color.primary)
            }
            PlaneGameCardChoices(
                title: Text("Play Again", tableName: "PlaneGame", bundle: .module, comment: "Starts another game"),
                action: playAgain, exit: exit)
        }
        .planeGameCard()
    }

    private var best: Text {
        result.isNewBest
            ? Text("New Best", tableName: "PlaneGame", bundle: .module, comment: "A game that beat the best score")
            : Text("Best", tableName: "PlaneGame", bundle: .module, comment: "The best score on this device")
    }

    private func figure(_ label: Text, value: Int) -> some View {
        VStack(spacing: 2) {
            label
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: value.formatted(.number))
                .font(.title.bold())
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
