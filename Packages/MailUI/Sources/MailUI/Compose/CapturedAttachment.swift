import MailCore
import UIKit

/// Turns what the camera and the document scanner produce into message attachments. Encoding a photo or a
/// multi-page scan takes long enough to stall the screen, so it runs off the main actor.
nonisolated enum CapturedAttachment {
    /// Turns one capture into its attachment, off the main actor.
    typealias Preparation = @Sendable () async throws -> DraftAttachment

    enum Failure: Error {
        case noPages
        case encodingFailed
    }

    /// Larger pictures are scaled down to this many pixels on the long side, which keeps a photo around 1 MB.
    static let maxDimension: CGFloat = 2560
    static let jpegQuality: CGFloat = 0.8
    /// A scanned page is laid out this wide in PDF points (US Letter); its height follows the page's proportions.
    static let pageWidth: CGFloat = 612

    @concurrent
    static func photo(_ image: UIImage, at date: Date, in timeZone: TimeZone = .current) async throws
        -> DraftAttachment
    {
        let data = try jpeg(image)
        return DraftAttachment(
            filename: filename("Photo", extension: "jpg", at: date, in: timeZone), mimeType: "image/jpeg", data: data)
    }

    /// One PDF with a page per scanned image, in order. Each page goes in as the JPEG of its scaled image: the PDF
    /// embeds those bytes as they are, without decoding them, so a page costs a few hundred KB rather than the
    /// tens of MB its bitmap would.
    @concurrent
    static func scan(pages: [UIImage], at date: Date, in timeZone: TimeZone = .current) async throws
        -> DraftAttachment
    {
        guard !pages.isEmpty else { throw Failure.noPages }
        let images = try pages.map { page in
            try Task.checkCancellation()
            guard let image = UIImage(data: try jpeg(page)) else { throw Failure.encodingFailed }
            return image
        }
        let data = UIGraphicsPDFRenderer(bounds: .zero).pdfData { context in
            for image in images {
                let size = CGSize(
                    width: pageWidth, height: (pageWidth * image.size.height / image.size.width).rounded())
                context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        return DraftAttachment(
            filename: filename("Scan", extension: "pdf", at: date, in: timeZone), mimeType: "application/pdf",
            data: data)
    }

    /// "Scan 2026-11-12 14.30.pdf": digits and dots only, so every file system accepts it.
    static func filename(_ prefix: String, extension pathExtension: String, at date: Date, in timeZone: TimeZone)
        -> String
    {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "\(prefix) \(formatter.string(from: date)).\(pathExtension)"
    }

    private static func jpeg(_ image: UIImage) throws -> Data {
        let longSide = max(image.size.width, image.size.height)
        let scaled: UIImage
        if longSide > maxDimension {
            let ratio = maxDimension / longSide
            let size = CGSize(
                width: (image.size.width * ratio).rounded(), height: (image.size.height * ratio).rounded())
            let format = UIGraphicsImageRendererFormat.preferred()
            format.scale = 1
            scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        } else {
            scaled = image
        }
        guard let data = scaled.jpegData(compressionQuality: jpegQuality) else { throw Failure.encodingFailed }
        return data
    }
}
