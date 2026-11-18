import SwiftUI

/// The card a paused game waits under: carry on, or go back to the Inbox.
struct PlaneGamePauseCard: View {
    let resume: () -> Void
    let exit: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Paused", tableName: "PlaneGame", bundle: .module, comment: "Title of the card over a paused game")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            PlaneGameCardChoices(
                title: Text("Resume", tableName: "PlaneGame", bundle: .module, comment: "Carries on a paused game"),
                action: resume, exit: exit)
        }
        .planeGameCard()
    }
}
