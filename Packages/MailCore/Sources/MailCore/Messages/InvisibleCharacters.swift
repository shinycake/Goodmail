/// Characters that show nothing: newsletters repeat them after the preview line so inboxes show no more of it, and
/// Apple Mail's plain part writes U+FFFC for each picture. The reader's view and every snippet leave them out alike.
enum InvisibleCharacters {
    /// `text` without them. A zero-width joiner or non-joiner with a character on either side still joins it, as in a
    /// family emoji, a Persian word or a Devanagari half-form; one between spaces, the text's ends or other joiners
    /// joins nothing. Direction marks stay for Hebrew and Arabic.
    static func removed(from text: String) -> String {
        let scalars = Array(text.unicodeScalars.filter { !invisible.contains($0.value) })
        func joinsNothing(_ index: Int) -> Bool {
            guard scalars.indices.contains(index) else { return true }
            return scalars[index].properties.isWhitespace || joiners.contains(scalars[index].value)
        }
        let kept = scalars.indices.lazy
            .filter { !joiners.contains(scalars[$0].value) || !(joinsNothing($0 - 1) && joinsNothing($0 + 1)) }
            .map { scalars[$0] }
        return String(String.UnicodeScalarView(kept))
    }

    /// Soft hyphen, combining grapheme joiner, Hangul and Khmer fillers, zero-width space,
    /// word joiner and invisible operators, byte order mark, object replacement character.
    private static let invisible: Set<UInt32> = [
        0x00AD, 0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x200B, 0x2060, 0x2061, 0x2062, 0x2063, 0x2064, 0x3164,
        0xFEFF, 0xFFA0, 0xFFFC,
    ]
    /// Zero-width non-joiner and joiner.
    private static let joiners: Set<UInt32> = [0x200C, 0x200D]
}
