import MailCore
import SwiftUI
import UIKit

extension MailService {
    /// How the service is pictured wherever the app shows it: its own logo, or a neutral symbol for any other server.
    enum Mark: Equatable {
        /// The brand's logo, a vector PDF among the module's resources, drawn in its own colors.
        case logo(String)
        /// An SF Symbol, tinted as the surrounding text.
        case symbol(String)
    }

    var mark: Mark {
        switch self {
        case .gmail: .logo("GmailLogo")
        case .icloud: .logo("ICloudLogo")
        case .outlook: .logo("OutlookLogo")
        case .imap: .symbol("at")
        }
    }

    /// The mark as a UIKit image, for menus and list headers. A logo keeps its colors under any tint.
    var markImage: UIImage? {
        switch mark {
        case .logo(let name): ServiceLogoImages.image(named: name)
        case .symbol(let name): UIImage(systemName: name)
        }
    }
}

/// The service's mark, sized to sit in a label's icon slot beside body text.
struct ServiceLogo: View {
    let service: MailService
    @ScaledMetric(relativeTo: .body) private var side = 24

    var body: some View {
        Group {
            switch service.mark {
            case .logo(let name):
                if let image = ServiceLogoImages.image(named: name) {
                    // A brand's colors, kept as they are under Smart Invert.
                    Image(uiImage: image).resizable().scaledToFit().accessibilityIgnoresInvertColors()
                }
            case .symbol(let name): Image(systemName: name).imageScale(.large)
            }
        }
        .frame(width: side, height: side)
        // The service's name is beside it, so the mark is decoration.
        .accessibilityHidden(true)
    }
}

/// The logos, drawn once from their PDFs. They ship as plain PDFs rather than an asset catalog, which only Xcode's
/// asset compiler can build and the Linux iOS build has none. Each mark is the brand's full-color logo, the same in
/// light and dark, as each brand's guidelines show it on either background.
enum ServiceLogoImages {
    /// Drawn big enough to stay sharp when scaled down to any icon slot, up to the largest accessibility size.
    private static let side: CGFloat = 64
    private static var drawn: [String: UIImage] = [:]

    static func image(named name: String) -> UIImage? {
        if let image = drawn[name] { return image }
        guard let page = page(named: name), let ink = inkedBounds(of: page) else { return nil }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            // Each logo's own artwork, not its artboard, fills the square: the brands pad their files differently
            // (Google's has a margin built in, a wide mark leaves its box half empty), and the marks sit side by side.
            let scale = side / max(ink.width, ink.height)
            let cg = context.cgContext
            // PDF space runs bottom-up.
            cg.translateBy(x: side / 2, y: side / 2)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -ink.midX, y: -ink.midY)
            cg.drawPDFPage(page)
        }
        .withRenderingMode(.alwaysOriginal)
        drawn[name] = image
        return image
    }

    static func page(named name: String) -> CGPDFPage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "pdf") else { return nil }
        return CGPDFDocument(url as CFURL)?.page(at: 1)
    }

    /// The part of the page that is drawn on, in the page's own space, found to within a 256th of the page.
    static func inkedBounds(of page: CGPDFPage) -> CGRect? {
        let box = page.getBoxRect(.mediaBox)
        let pixels = 256
        let scale = CGFloat(pixels) / max(box.width, box.height)
        guard let bitmap = RGBABitmap(width: pixels, height: pixels) else { return nil }
        bitmap.context.scaleBy(x: scale, y: scale)
        bitmap.context.translateBy(x: -box.minX, y: -box.minY)
        bitmap.context.drawPDFPage(page)
        guard let rgba = bitmap.pixels else { return nil }
        var (minX, minY, maxX, maxY) = (pixels, pixels, -1, -1)
        for row in 0..<pixels {
            for column in 0..<pixels where rgba[4 * (row * pixels + column) + 3] > 8 {
                // The first row in memory is the top of the page, which is its highest y.
                let y = pixels - 1 - row
                (minX, maxX) = (min(minX, column), max(maxX, column))
                (minY, maxY) = (min(minY, y), max(maxY, y))
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(
            x: box.minX + CGFloat(minX) / scale, y: box.minY + CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }
}
