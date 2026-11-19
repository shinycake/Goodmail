import Foundation
import MailCore
import PDFKit
import Testing
import UIKit

@testable import MailUI

/// A conversation laid out for print or sharing comes back as pages that carry its words, in time.
@MainActor
struct ConversationPDFTests {
    private func message(_ number: Int, from name: String, body: String) -> Message {
        Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m\(number)"), threadID: "t",
            from: Contact(name: name, address: "\(name.lowercased())@example.com"),
            to: [Contact(name: nil, address: "me@example.com")], subject: "Plan",
            date: Date(timeIntervalSince1970: 1_800_000_000 + Double(number) * 60),
            body: MessageBody(html: "<html><body><p>\(body)</p></body></html>"))
    }

    @Test(.timeLimit(.minutes(1)))
    func aTwoMessageConversationPrintsItsWords() async throws {
        let data = try await ConversationPDF.data(
            for: [
                message(1, from: "Dana", body: "Thursday works for me."), message(2, from: "Yael", body: "בטח, נתראה."),
            ],
            subject: "Plan for Thursday", appearance: { _ in .light }, allowsRemoteContent: [],
            attachmentData: { _, _ in Data() })

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2, "each short message fills one page, with none left blank")
        let text = try #require(document.string)
        #expect(text.contains("Plan for Thursday"))
        #expect(text.contains("Thursday works for me."))
        #expect(text.contains("נתראה"))
    }

    @Test(.timeLimit(.minutes(1)))
    func aLongMessageRunsOnToMorePages() async throws {
        let paragraphs = (1...120).map { "Line \($0) of the agenda." }.joined(separator: "</p><p>")
        let data = try await ConversationPDF.data(
            for: [message(1, from: "Dana", body: paragraphs)], subject: "Agenda", appearance: { _ in .light },
            allowsRemoteContent: [],
            attachmentData: { _, _ in Data() })

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 2)
        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        #expect(pages.allSatisfy { !$0.isEmpty }, "no page is left blank")
        #expect(pages.last?.contains("Line 120 of the agenda.") == true, "the end of the message reaches the last page")
    }

    /// A sender's own dark styles that miss their white panel, as a delivery notice's did: in dark its text turned
    /// white on white, and the PDF, whatever the screen showed, came out that way.
    private let paintedNotice = """
        <html><head><style>@media (prefers-color-scheme: dark) { .ink { color: #ffffff !important; } }</style></head>\
        <body><table width="100%" bgcolor="#ffffff"><tr><td class="ink" style="color: #0d1b4c; height: 300px">\
        Hi Idan</td></tr></table></body></html>
        """

    /// The color of the first page at `point`, in PDF points from its top left.
    private func color(of data: Data, at point: CGPoint) throws -> [Int] {
        let page = try #require(PDFDocument(data: data)?.page(at: 0))
        let box = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { context in
            // PDF space runs up from the bottom: flip it, then move the point to the one pixel there is.
            context.cgContext.translateBy(x: -point.x, y: box.height - point.y)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        let cgImage = try #require(image.cgImage)
        let bytes = [UInt8](try #require(cgImage.dataProvider?.data as Data?))
        // Where red, green and blue sit in the pixel's four bytes.
        let alphaFirst = [.first, .premultipliedFirst, .noneSkipFirst].contains(cgImage.alphaInfo)
        let little = cgImage.byteOrderInfo == .order32Little
        let order = alphaFirst ? (little ? [2, 1, 0] : [1, 2, 3]) : (little ? [3, 2, 1] : [0, 1, 2])
        return order.map { Int(bytes[$0]) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [UIUserInterfaceStyle.light, .dark])
    func eachMessagePrintsInTheAppearanceItShowsIn(style: UIUserInterfaceStyle) async throws {
        let notice = Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "fetch"), threadID: "t",
            from: Contact(name: "Fetch", address: "notifications@example.com"), to: [], subject: "Your package",
            date: Date(timeIntervalSince1970: 1_800_000_000), body: MessageBody(html: paintedNotice))
        let data = try await ConversationPDF.data(
            for: [notice], subject: "Your package", appearance: { _ in style }, allowsRemoteContent: [],
            attachmentData: { _, _ in Data() })

        let margin = try color(of: data, at: CGPoint(x: 10, y: 10))
        let panel = try color(of: data, at: CGPoint(x: 300, y: 280))
        switch style {
        case .dark:
            #expect(margin.allSatisfy { (20...36).contains($0) }, "the page is the dark card: \(margin)")
            #expect(panel.allSatisfy { (35...55).contains($0) }, "the white panel is turned dark: \(panel)")
        default:
            #expect(margin == [255, 255, 255])
            #expect(panel.allSatisfy { $0 > 245 }, "the sender's dark styles stay out of a light page: \(panel)")
        }
    }
}
