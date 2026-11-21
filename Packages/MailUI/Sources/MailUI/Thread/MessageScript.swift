import Foundation
import MailCore

/// Runs in Goodmail's own content world after each message loads. Email JavaScript stays off (ADR-003); this script
/// is ours, and the sender's page can neither see nor call it.
///
/// The script is plain JavaScript in `Resources/message-*.js`, one part per job. Swift writes only a header with the
/// values the script shares with the app, so each has one source. Then `message-shared.js` runs, and each other part
/// in a block of its own, so a part sees the header and the shared names but never another part's.
nonisolated enum MessageScript {
    static let handlerName = "goodmail"

    /// What the script is run for.
    enum Purpose {
        /// The reader's card: it folds quoted history behind a control labeled `foldLabel`, and reports the body's
        /// height to size the card.
        case reader(foldLabel: String)
        /// A page of a PDF: every quote shows, and the page's height is its own, so nothing is reported.
        case paper
    }

    /// The parts after `shared`, in the order they run. The order matters for what each leaves in the page: size comes
    /// first, so fonts reads the body's pinned system font, the fold comes before contrast, which skips our fold
    /// control, and layout comes last, since it measures the finished page.
    private static let parts = ["size", "direction", "fold", "fonts", "contrast", "dark", "links", "find", "layout"]

    /// The script after its header, read from the bundle once. A part missing from the bundle is a broken build, so it
    /// stops the app rather than show mail without its script.
    private static let body: String = {
        let blocks = parts.map { "{\n\(resource($0))}" }
        return ([resource("shared")] + blocks).joined(separator: "\n")
    }()

    private static func resource(_ part: String) -> String {
        guard let url = Bundle.module.url(forResource: "message-\(part)", withExtension: "js"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { preconditionFailure("message-\(part).js is missing from MailUI's resources") }
        return text
    }

    static func source(for purpose: Purpose) -> String {
        let foldLabel: String? =
            switch purpose {
            case .reader(let label): label
            case .paper: nil
            }
        return """
            (() => {
            const READER = \(foldLabel != nil);
            const FOLD_LABEL = \(jsonString(foldLabel ?? ""));
            const HANDLER = \(jsonString(handlerName));
            const CARD = [\(ReaderColors.list(ReaderColors.darkCard))];
            const CARD_LIGHT = [\(ReaderColors.list(ReaderColors.lightCard))];
            const SHEET = [\(ReaderColors.list(ReaderColors.darkSheet))];
            \(body)
            })();
            """
    }

    /// Zooms a loaded reader page to `zoom`; the page reports its new height.
    static func zoom(to zoom: ReaderZoom) -> String {
        "window.goodmailZoom(\(zoom.factor))"
    }

    private static func jsonString(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [text])
        return data.map { String(decoding: $0.dropFirst().dropLast(), as: UTF8.self) } ?? "\"\""
    }
}
