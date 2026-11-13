import CoreGraphics
import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

@MainActor
struct CapturedAttachmentTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-12 14:30:45 UTC.
    private let date = Date(timeIntervalSince1970: 1_794_493_845)

    private func image(width: CGFloat, height: CGFloat, color: UIColor = .systemTeal) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pdf(_ attachment: DraftAttachment) throws -> CGPDFDocument {
        let data = try #require(attachment.data)
        let provider = try #require(CGDataProvider(data: data as CFData))
        return try #require(CGPDFDocument(provider))
    }

    @Test func namesAScanAfterWhenItWasTaken() async throws {
        let scan = try await CapturedAttachment.scan(pages: [image(width: 300, height: 400)], at: date, in: utc)
        #expect(scan.filename == "Scan 2026-11-12 14.30.pdf")
        #expect(scan.mimeType == "application/pdf")
    }

    @Test func putsEveryScannedPageInOnePDFInOrder() async throws {
        let scan = try await CapturedAttachment.scan(
            pages: [image(width: 300, height: 600), image(width: 800, height: 400), image(width: 500, height: 500)],
            at: date, in: utc)
        let document = try pdf(scan)
        #expect(document.numberOfPages == 3)
        let sizes = (1...3).compactMap { document.page(at: $0)?.getBoxRect(.mediaBox).size }
        #expect(sizes.map(\.width) == [612, 612, 612])
        #expect(sizes.map(\.height) == [1224, 306, 612], "each page keeps its proportions")
    }

    @Test func refusesAScanWithNoPages() async {
        await #expect(throws: CapturedAttachment.Failure.noPages) {
            try await CapturedAttachment.scan(pages: [], at: date, in: utc)
        }
    }

    @Test func keepsAScanSmallEnoughToSend() async throws {
        let scan = try await CapturedAttachment.scan(pages: [image(width: 3000, height: 4000)], at: date, in: utc)
        #expect(try #require(scan.data).count < 1_000_000)
    }

    @Test func encodesAPhotoAsJPEG() async throws {
        let photo = try await CapturedAttachment.photo(image(width: 400, height: 300), at: date, in: utc)
        #expect(photo.filename == "Photo 2026-11-12 14.30.jpg")
        #expect(photo.mimeType == "image/jpeg")
        let data = try #require(photo.data)
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size == CGSize(width: 400, height: 300), "small photos keep their size")
    }

    @Test func shrinksALargePhotoKeepingItsProportions() async throws {
        let photo = try await CapturedAttachment.photo(image(width: 4000, height: 3000), at: date, in: utc)
        let data = try #require(photo.data)
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size == CGSize(width: 2560, height: 1920))
    }

    @Test func namesFilesInTheGivenTimeZone() {
        let jerusalem = TimeZone(identifier: "Asia/Jerusalem")!
        #expect(
            CapturedAttachment.filename("Scan", extension: "pdf", at: date, in: jerusalem)
                == "Scan 2026-11-12 16.30.pdf")
    }
}
