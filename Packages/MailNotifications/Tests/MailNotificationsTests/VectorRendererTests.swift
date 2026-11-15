import CoreGraphics
import Foundation
import ImageIO
import MailCore
import Testing

@testable import MailNotifications

struct VectorRendererTests {
    /// The RGBA bytes of the rendered PNG, top row first.
    private func pixels(_ svg: String, side: Int = 20) throws -> (Int, Int) -> [UInt8] {
        let image = try #require(SVGDocument.image(from: Data(svg.utf8)))
        let png = try #require(VectorRenderer.png(of: image, side: side))
        let decoded = try #require(
            CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let context = try #require(
            CGContext(
                data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: side, height: side))
        let copy = bytes
        return { x, y in Array(copy[(y * side + x) * 4..<(y * side + x) * 4 + 3]) }
    }

    @Test func shapesLandWhereSVGPutsThemOnWhite() throws {
        // A blue band across the top fifth; SVG's y runs down, Core Graphics' up.
        let pixel = try pixels(
            ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="2" fill="#00f"/></svg>"##
        )
        #expect(pixel(10, 1) == [0, 0, 255])
        #expect(pixel(10, 18) == [255, 255, 255])
    }

    @Test func aWideViewBoxIsFittedAndCentered() throws {
        // 20 by 10, fitted into a square: the picture fills the middle half, from y 5 to 15.
        let pixel = try pixels(
            ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10"><rect width="20" height="10" fill="red"/></svg>"##
        )
        #expect(pixel(10, 2) == [255, 255, 255])
        #expect(pixel(10, 10) == [255, 0, 0])
    }

    @Test func gradientsSpanTheShapesBounds() throws {
        let pixel = try pixels(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
              <linearGradient id="g"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>
              <rect width="10" height="10" fill="url(#g)"/>
            </svg>
            """)
        let left = pixel(1, 10)[0]
        let right = pixel(18, 10)[0]
        #expect(left < 40)
        #expect(right > 215)
    }
}
