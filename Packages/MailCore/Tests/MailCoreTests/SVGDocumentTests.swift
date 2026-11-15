import Foundation
import Testing

@testable import MailCore

struct SVGDocumentTests {
    private func image(_ svg: String) throws -> VectorImage {
        try #require(SVGDocument.image(from: Data(svg.utf8)))
    }

    private func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> VectorPaint {
        .color(VectorColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha))
    }

    /// PayPal's BIMI logo as published, trimmed to two of its paths.
    @Test func aBIMILogoParsesIntoItsShapesAndColors() throws {
        let logo = try image(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <svg xmlns="http://www.w3.org/2000/svg" baseProfile="tiny-ps" version="1.2" viewBox="0 0 700 700">
              <!-- Generator: Adobe Illustrator 28.6.0 -->
            <title>PayPal</title>
              <g><g id="Avatar">
                <rect width="700" height="700" fill="#fff"/>
                <path d="M177.6,487h91.3l17.2-111.8h0Z" fill="#002991"/>
                <path d="M489.6,230.7s0,0,0,0c0-.9,0-1,0,0h0s0,0,0,0Z"/>
              </g></g>
            </svg>
            """)
        #expect(logo.viewBox == VectorRect(x: 0, y: 0, width: 700, height: 700))
        #expect(logo.shapes.map(\.fill) == [color(255, 255, 255), color(0, 0x29, 0x91), .color(.black)])
        #expect(logo.shapes[1].path.first == .move(VectorPoint(x: 177.6, y: 487)))
    }

    @Test func styleSheetsOverrideAttributesAndStyleAttributesOverrideBoth() throws {
        let logo = try image(
            """
            <svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg">
              <style><![CDATA[ .a { fill: #f00 } /* red */ path.b { fill: rgb(0, 255, 0) } #c { fill: blue } ]]></style>
              <path class="a" fill="#000" d="M0 0h1v1z"/>
              <path class="a b" d="M0 0h1v1z"/>
              <path id="c" class="b" d="M0 0h1v1z"/>
              <path class="a" style="fill: #00f; fill-opacity: 0.5" d="M0 0h1v1z"/>
            </svg>
            """)
        #expect(
            logo.shapes.map(\.fill) == [
                color(255, 0, 0), color(0, 255, 0), color(0, 0, 255), color(0, 0, 255, 0.5),
            ])
    }

    @Test func groupsPassOnStyleTransformsAndOpacity() throws {
        let logo = try image(
            """
            <svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg">
              <g fill="red" opacity="0.5" transform="translate(5 0)">
                <rect transform="scale(2)" width="1" height="1"/>
                <g display="none"><rect width="1" height="1"/></g>
              </g>
            </svg>
            """)
        let shape = try #require(logo.shapes.first)
        #expect(logo.shapes.count == 1)
        #expect(shape.fill == color(255, 0, 0, 0.5))
        // Scaled first, then moved: (1, 1) lands on (7, 2).
        #expect(shape.transform.apply(to: VectorPoint(x: 1, y: 1)) == VectorPoint(x: 7, y: 2))
    }

    @Test func gradientsInheritStopsThroughHref() throws {
        let logo = try image(
            """
            <svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
              <defs>
                <linearGradient id="base"><stop offset="0" stop-color="#000"/><stop offset="100%" style="stop-color:#fff"/></linearGradient>
                <linearGradient id="g" xlink:href="#base" x2="0" y2="1"/>
              </defs>
              <circle cx="5" cy="5" r="5" fill="url(#g)"/>
            </svg>
            """)
        let gradient = LinearGradient(
            start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 0, y: 1),
            stops: [
                GradientStop(offset: 0, color: VectorColor(red: 0, green: 0, blue: 0)),
                GradientStop(offset: 1, color: VectorColor(red: 1, green: 1, blue: 1)),
            ], units: .objectBoundingBox)
        #expect(logo.shapes.map(\.fill) == [.linearGradient(gradient)])
    }

    @Test func useDrawsTheElementItNamesAtItsOffset() throws {
        let logo = try image(
            """
            <svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
              <defs><rect id="dot" width="1" height="1"/></defs>
              <use xlink:href="#dot" x="3" y="4" fill="#0f0"/>
              <use href="#loop" id="loop"/>
            </svg>
            """)
        let shape = try #require(logo.shapes.first)
        #expect(logo.shapes.count == 1)
        #expect(shape.fill == color(0, 255, 0))
        #expect(shape.transform.apply(to: VectorPoint(x: 0, y: 0)) == VectorPoint(x: 3, y: 4))
    }

    @Test func noneAndStrokesAreHonored() throws {
        let logo = try image(
            """
            <svg width="20" height="10" xmlns="http://www.w3.org/2000/svg">
              <rect width="5" height="5" fill="none"/>
              <line x1="0" y1="0" x2="5" y2="5" stroke="#000" stroke-width="2" stroke-linecap="round"/>
            </svg>
            """)
        #expect(logo.viewBox == VectorRect(x: 0, y: 0, width: 20, height: 10))
        #expect(logo.shapes.count == 1)
        #expect(logo.shapes[0].fill == nil)
        #expect(logo.shapes[0].stroke == VectorStroke(paint: color(0, 0, 0), width: 2, cap: .round))
    }

    @Test func aDocumentThatMultipliesItsWorkThroughUseHasNoImage() {
        // Ten uses of the next group at each of nine levels: 10^9 rectangles from a few hundred bytes.
        let groups = (0..<9).map { level in
            ##"<g id="g\##(level)">"## + String(repeating: ##"<use href="#g\##(level + 1)"/>"##, count: 10) + "</g>"
        }
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
              <defs>\(groups.joined())<rect id="g9" width="1" height="1"/></defs>
              <use href="#g0"/>
            </svg>
            """
        #expect(SVGDocument.image(from: Data(svg.utf8)) == nil)
    }

    @Test func dataThatIsNotSVGHasNoImage() {
        #expect(SVGDocument.image(from: Data("<html><body/></html>".utf8)) == nil)
        #expect(SVGDocument.image(from: Data("not xml".utf8)) == nil)
    }
}
