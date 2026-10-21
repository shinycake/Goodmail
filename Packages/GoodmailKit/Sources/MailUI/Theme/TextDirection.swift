import UIKit

/// The paragraph direction of a piece of content, from its first strongly directional character (the
/// Unicode bidi "first strong" rule), so Hebrew mail reads right to left in an English UI and vice versa.
nonisolated enum TextDirection: Equatable {
    case leftToRight
    case rightToLeft

    /// `nil` when the text has no letters to decide by, such as "12:30" or an empty string.
    static func of(_ text: String) -> TextDirection? {
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            return isRightToLeft(scalar) ? .rightToLeft : .leftToRight
        }
        return nil
    }

    private static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF,  // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic, Arabic Extended
            0xFB1D...0xFDFF,  // Hebrew and Arabic presentation forms
            0xFE70...0xFEFF,  // Arabic presentation forms B
            0x10800...0x10FFF,  // Historic right-to-left scripts
            0x1E800...0x1EFFF:  // Mende Kikakui, Adlam, Arabic mathematical symbols
            true
        default:
            false
        }
    }
}

extension UILabel {
    /// Sets `text` laid out in its own direction, so punctuation lands on the correct side. With
    /// `alignedToContent`, the paragraph also aligns to where that language starts; otherwise it follows the
    /// interface, for text that sits beside other elements. Text with no letters follows the interface.
    func setContentText(_ text: String, alignedToContent: Bool = true) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .natural
        switch TextDirection.of(text) {
        case .leftToRight:
            paragraph.baseWritingDirection = .leftToRight
            if alignedToContent { paragraph.alignment = .left }
        case .rightToLeft:
            paragraph.baseWritingDirection = .rightToLeft
            if alignedToContent { paragraph.alignment = .right }
        case nil:
            break
        }
        if !alignedToContent {
            // `.natural` would follow the base direction just set; pin to the interface's leading edge instead.
            paragraph.alignment = effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        }
        attributedText = NSAttributedString(
            string: text,
            attributes: [.paragraphStyle: paragraph, .font: font as Any, .foregroundColor: textColor as Any]
        )
    }
}
