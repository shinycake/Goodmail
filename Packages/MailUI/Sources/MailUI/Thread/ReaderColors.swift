import Foundation

/// The reader's own colors that the message script and the pages around a message share, as sRGB channels, so each
/// has one source. `MessageScript` writes them into the script's header.
nonisolated enum ReaderColors {
    /// The reader's dark card, which a message shows on in dark.
    static let darkCard = [28, 28, 30]
    /// The reader's light card.
    static let lightCard = [242, 242, 247]
    /// The dark of a white page: the gray white turns into, a shade above the dark card so the email still reads as a
    /// sheet. The dark pass (`message-dark.js`) turns a lightness of 1 into this same gray.
    static let darkSheet = [43, 43, 43]

    /// `channels` as CSS, such as `rgb(43, 43, 43)`.
    static func css(_ channels: [Int]) -> String {
        "rgb(\(list(channels)))"
    }

    /// `channels` as the body of a JavaScript array or a CSS color, such as `43, 43, 43`.
    static func list(_ channels: [Int]) -> String {
        channels.map(String.init).joined(separator: ", ")
    }
}
