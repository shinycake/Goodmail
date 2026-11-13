import Foundation

/// A message body as the writer formatted it: paragraphs, each laid out as plain text, a list item or a quote,
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
        var direction: Direction = .auto
        /// Never two neighbours with the same style and link, and never an empty one.
        private(set) var runs: [Run] = []

        init(block: Block = .body, direction: Direction = .auto, runs: [Run] = []) {
            self.block = block
            self.direction = direction
            for run in runs { append(run) }
        }

        var text: String { runs.map(\.text).joined() }

        mutating func append(_ run: Run) {
            guard !run.text.isEmpty else { return }
            if let last = runs.last, last.styles == run.styles, last.link == run.link {
                runs[runs.count - 1].text += run.text
            } else {
                runs.append(run)
            }
        }
    }

    /// How a paragraph is laid out. A list item or a quote joins its neighbours of the same kind into one list or
    /// one quote.
    enum Block: CaseIterable, Equatable {
        case body, bulleted, numbered, quote
    }

    /// Which way a paragraph reads: from what is typed in it, or as the writer set it.
    enum Direction: String, CaseIterable, Equatable {
        case auto
        case leftToRight = "ltr"
        case rightToLeft = "rtl"

        /// The way `text` reads by its first letter, as `dir="auto"` decides: right to left for Hebrew or Arabic,
        /// left to right for any other letter or when there is none.
        static func detected(in text: String) -> Direction {
            for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
                return isRightToLeft(scalar) ? .rightToLeft : .leftToRight
            }
            return .leftToRight
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
    }

    enum Style: CaseIterable, Hashable {
        case bold, italic, underline, strikethrough
    }

    /// The text with its layout spelled out, for the plain alternative: bullets, numbers and `>` before quoted lines.
    var plain: String {
        var number = 0
        return paragraphs.map { paragraph in
            number = paragraph.block == .numbered ? number + 1 : 0
            let marker =
                switch paragraph.block {
                case .body: ""
                case .bulleted: "• "
                case .numbered: "\(number). "
                case .quote: "> "
                }
            return marker + paragraph.text
        }
        .joined(separator: "\n")
    }

    /// Neighbouring paragraphs that share a list or a quote, in order. A body paragraph stands alone.
    var groups: [ArraySlice<Paragraph>] {
        var groups: [ArraySlice<Paragraph>] = []
        var start = 0
        for index in paragraphs.indices.dropFirst() {
            let block = paragraphs[index].block
            if block == .body || block != paragraphs[index - 1].block {
                groups.append(paragraphs[start..<index])
                start = index
            }
        }
        groups.append(paragraphs[start...])
        return groups
    }
}
