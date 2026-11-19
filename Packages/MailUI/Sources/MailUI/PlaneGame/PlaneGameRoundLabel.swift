import SwiftUI

/// The round being played, under the score between bosses and over a boss's name as it arrives.
struct PlaneGameRoundLabel: View {
    let round: Int
    var font: Font = .caption.weight(.semibold)

    var body: some View {
        Text(
            "Round \(round)", tableName: "PlaneGame", bundle: .module,
            comment: "The round of the paper plane game being played"
        )
        .font(font.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
