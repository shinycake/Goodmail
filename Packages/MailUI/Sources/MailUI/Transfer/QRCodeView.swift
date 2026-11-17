import CoreImage.CIFilterBuiltins
import SwiftUI

/// `text` as a QR code, its modules kept sharp at any size.
struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(16)
                // Dark modules on white whatever the appearance, which every scanner reads.
                .background(.white, in: .rect(cornerRadius: 16))
                // Smart Invert would flip the code to light on dark, which some scanners can't read.
                .accessibilityIgnoresInvertColors()
        }
    }

    private static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
