import MailCore
import SwiftUI

extension MailCore.RGBColor {
    /// A color as the color picker hands it back, resolved for where it was picked, at 8 bits a channel.
    /// Wide-gamut colors are clamped to sRGB.
    init(_ color: Color.Resolved) {
        self.init(fractionalRed: Double(color.red), green: Double(color.green), blue: Double(color.blue))
    }
}
