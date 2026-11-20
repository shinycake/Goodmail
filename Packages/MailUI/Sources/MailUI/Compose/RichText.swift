import Foundation
import MailCore

/// A message body as the writer formatted it: paragraphs, each plain text or a list item, quoted to some depth,
/// reading in its own direction, made of styled runs. The editor's text and the HTML that is sent both convert to
/// and from this, so each format is described once.
nonisolated struct RichText: Equatable {
    var paragraphs: [Paragraph]

    init(_ paragraphs: [Paragraph] = [Paragraph()]) {
        self.paragraphs = paragraphs.isEmpty ? [Paragraph()] : paragraphs
    }

    /// Unformatted text, one paragraph per line.
    init(plain: String) {
        self.init(plain.components(separatedBy: "\n").map { Paragraph(runs: [Run(text: $0)]) })
    }

    struct Paragraph: Equatable {
        var block: Block = .body
        /// How many quotes the paragraph sits in: 0 for none, 2 for a quote inside a quote. A list item can be quoted.
        var quoteLevel: QuoteLevel = .none
        var direction: Direction = .auto
        /// Never two neighbours with the same format, and never an empty one.
        private(set) var runs: [Run] = []

        init(block: Block = .body, quoteLevel: QuoteLevel = .none, direction: Direction = .auto, runs: [Run] = []) {
            self.block = block
            self.quoteLevel = quoteLevel
            self.direction = direction
            for run in runs { append(run) }
        }

        var text: String { runs.map(\.text).joined() }

        mutating func append(_ run: Run) {
            guard !run.text.isEmpty else { return }
            if let last = runs.last, last.hasFormat(of: run) {
                runs[runs.count - 1].text += run.text
            } else {
                runs.append(run)
            }
        }
    }

    /// How a paragraph is laid out. A list item joins its neighbours of the same kind, at the same quote level, into
    /// one list.
    enum Block: CaseIterable, Equatable {
        case body, bulleted, numbered
    }

    /// How deeply a paragraph is quoted. Neighbours quoted at least as deeply share each quote, as nested
    /// `blockquote`s do, so a quote's bar runs unbroken past a deeper one inside it.
    struct QuoteLevel: RawRepresentable, Comparable, Hashable {
        static let none = QuoteLevel(rawValue: 0)
        /// Past this many bars a writer can no longer tell the levels apart.
        static let deepest = QuoteLevel(rawValue: maxDepth)
        private static let maxDepth = 4

        let rawValue: Int

        /// Clamped to `none...deepest`.
        init(rawValue: Int) { self.rawValue = min(max(rawValue, 0), Self.maxDepth) }

        var isQuoted: Bool { rawValue > 0 }
        var deeper: QuoteLevel { QuoteLevel(rawValue: rawValue + 1) }
        var shallower: QuoteLevel { QuoteLevel(rawValue: rawValue - 1) }

        static func < (lhs: QuoteLevel, rhs: QuoteLevel) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The bar of the quote at `depth` (1 for the outermost), as sent: a color for each level, as Apple Mail
        /// marks them, that reads on light and dark backgrounds alike.
        static func barHex(depth: Int) -> String {
            let colors = ["#1a73e8", "#2e9e44", "#e8790c"]
            return colors[(depth - 1) % colors.count]
        }
    }

    /// Which way a paragraph reads: from what is typed in it, or as the writer set it.
    enum Direction: String, CaseIterable, Equatable {
        case auto
        case leftToRight = "ltr"
        case rightToLeft = "rtl"

        /// The way `text` reads by its first letter, as `dir="auto"` decides: right to left for Hebrew or Arabic,
        /// left to right for any other letter or when there is none.
        static func detected(in text: String) -> Direction { firstLetter(in: text) ?? .leftToRight }

        /// The way `text`'s first letter reads; `nil` when it has none yet.
        static func firstLetter(in text: String) -> Direction? {
            for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
                return isRightToLeft(scalar) ? .rightToLeft : .leftToRight
            }
            return nil
        }

        private static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: true
            default: false
            }
        }
    }

    struct Run: Equatable {
        var text: String
        var styles: Set<Style> = []
        var link: URL?
        var size: Size = .normal
        var color: TextColor = .automatic

        func hasFormat(of other: Run) -> Bool {
            styles == other.styles && link == other.link && size == other.size && color == other.color
        }
    }

    /// Text sizes relative to the message's own, as Gmail and Apple Mail offer them.
    enum Size: String, CaseIterable, Equatable {
        case small, normal, large, huge

        var scale: Double {
            switch self {
            case .small: 0.8
            case .normal: 1
            case .large: 1.4
            case .huge: 2
            }
        }
    }

    /// The reader's own text color, or one the writer chose. A chosen color is sent as its fixed value, so it is
    /// first made one that reads on a light page and a dark one alike (`TextInk`), since a recipient's client may
    /// show either. The reader's own color is sent as no color at all, so each client uses its own.
    enum TextColor: Hashable {
        case automatic
        case ink(TextInk)

        init(_ chosen: RGBColor) { self = .ink(TextInk(chosen)) }
        init(_ preset: Preset) { self.init(preset.rgb) }

        /// The color as sent, `#rrggbb`; `nil` leaves the text the reader's color.
        var hex: String? {
            switch self {
            case .automatic: nil
            case .ink(let ink): ink.color.hex.lowercased()
            }
        }

        /// Strong colors offered at hand, beside the full picker.
        enum Preset: CaseIterable {
            case red, orange, green, blue, purple, gray

            var rgb: RGBColor {
                switch self {
                case .red: RGBColor(red: 0xE0, green: 0x35, blue: 0x2B)
                case .orange: RGBColor(red: 0xE8, green: 0x79, blue: 0x0C)
                case .green: RGBColor(red: 0x2E, green: 0x9E, blue: 0x44)
                case .blue: RGBColor(red: 0x1A, green: 0x73, blue: 0xE8)
                case .purple: RGBColor(red: 0x8E, green: 0x44, blue: 0xAD)
                case .gray: RGBColor(red: 0x8E, green: 0x8E, blue: 0x93)
                }
            }
        }
    }

    enum Style: CaseIterable, Hashable {
        case bold, italic, underline, strikethrough
    }

    /// The text with its layout spelled out, for the plain alternative: a `>` for each quote, then bullets and
    /// numbers.
    var plain: String {
        var number = 0
        var previous: Paragraph?
        return paragraphs.map { paragraph in
            let continuesList =
                previous.map { $0.block == paragraph.block && $0.quoteLevel == paragraph.quoteLevel } ?? false
            number = paragraph.block == .numbered ? (continuesList ? number + 1 : 1) : 0
            previous = paragraph
            let quote =
                paragraph.quoteLevel.isQuoted ? String(repeating: ">", count: paragraph.quoteLevel.rawValue) + " " : ""
            let marker =
                switch paragraph.block {
                case .body: ""
                case .bulleted: "• "
                case .numbered: "\(number). "
                }
            return quote + marker + paragraph.text
        }
        .joined(separator: "\n")
    }
}
