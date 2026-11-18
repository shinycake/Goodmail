import SwiftUI

/// The two ways on from a card over the game: the one the card is for, and the way back to the Inbox under it.
struct PlaneGameCardChoices: View {
    let title: Text
    let action: () -> Void
    let exit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                title.frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(DoodlePalette.purple)
            .controlSize(.large)
            Button(action: exit) {
                Text("Back to Inbox", tableName: "PlaneGame", bundle: .module, comment: "Leaves the paper plane game")
            }
            .buttonStyle(.borderless)
            .tint(DoodlePalette.purple)
            .controlSize(.large)
        }
    }
}

extension View {
    /// Sets the view on a card in the middle of the game: paper with a hairline edge, no wider than a phone.
    func planeGameCard() -> some View {
        padding(28)
            .frame(maxWidth: 340)
            .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.separator) }
            .padding(24)
    }
}
