import Foundation
import MailCore
import SwiftUI

extension AttributedString {
    /// A bubble's styled words as `Text` draws them: bold and italics through the font, and each link underlined, so
    /// it reads as one to tap in either bubble's color.
    init(_ styled: StyledText) {
        self.init()
        for run in styled.runs {
            var piece = AttributedString(run.text)
            var intent = InlinePresentationIntent()
            if run.style.contains(.bold) { intent.insert(.stronglyEmphasized) }
            if run.style.contains(.italic) { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if let link = run.link {
                piece.link = link
                piece.swiftUI.underlineStyle = .single
            }
            append(piece)
        }
    }
}
