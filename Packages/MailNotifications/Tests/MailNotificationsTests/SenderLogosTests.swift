import Foundation
import ImageIO
import MailCore
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import MailNotifications

struct SenderLogosTests {
    @Test func aFetchedLogoIsCachedForAMonth() async throws {
        let site = FakeSite(image: png(side: 120))
        let clock = Clock()
        let logos = SenderLogos(directory: try temporaryDirectory(), http: site, dns: FakeDNS(), now: { clock.now })

        #expect(await logos.logo(for: "a@github.com") != nil)
        clock.advance(by: 29 * 86_400)
        #expect(await logos.logo(for: "b@github.com") != nil)
        #expect(site.urls == ["https://github.com/apple-touch-icon.png"])

        clock.advance(by: 2 * 86_400)
        #expect(await logos.logo(for: "a@github.com") != nil)
        #expect(site.urls.count == 2)
    }

    @Test func aSiteWithoutAUsableLogoIsAskedAgainOnlyAfterAWeek() async throws {
        let site = FakeSite(image: png(side: 16))
        let clock = Clock()
        let logos = SenderLogos(directory: try temporaryDirectory(), http: site, dns: FakeDNS(), now: { clock.now })

        #expect(await logos.logo(for: "a@example.com") == nil)
        #expect(await logos.logo(for: "a@example.com") == nil)
        #expect(site.urls.count == 1)
        clock.advance(by: 8 * 86_400)
        _ = await logos.logo(for: "a@example.com")
        #expect(site.urls.count == 2)
    }

    @Test func aBIMILogoComesFirstAndIsDrawnAsAPNG() async throws {
        let svg = Data(
            ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="#002991"/></svg>"##
                .utf8)
        let site = FakeSite(image: svg)
        let dns = FakeDNS(["default._bimi.paypal.com": ["v=BIMI1; l=https://cdn.example/paypal.svg; a=;"]])
        let logos = SenderLogos(directory: try temporaryDirectory(), http: site, dns: dns)

        let logo = try #require(await logos.logo(for: "service@mail.paypal.com"))

        #expect(dns.names == ["default._bimi.mail.paypal.com", "default._bimi.paypal.com"])
        #expect(site.urls == ["https://cdn.example/paypal.svg"])
        let image = try #require(
            CGImageSourceCreateWithData(logo as CFData, nil).flatMap {
                CGImageSourceCreateImageAtIndex($0, 0, nil)
            })
        #expect(image.width == SenderLogos.renderedSide)
    }

    @Test func aDomainThatDeclinesBIMIFallsBackToItsSiteIcon() async throws {
        let site = FakeSite(image: png(side: 120))
        let dns = FakeDNS(["default._bimi.example.com": ["v=BIMI1; l=; a=;"]])
        let logos = SenderLogos(directory: try temporaryDirectory(), http: site, dns: dns)

        #expect(await logos.logo(for: "a@example.com") != nil)
        #expect(site.urls == ["https://example.com/apple-touch-icon.png"])
    }

    @Test func freeMailIsNeverLookedUp() async throws {
        let site = FakeSite(image: png(side: 120))
        let logos = SenderLogos(directory: try temporaryDirectory(), http: site, dns: FakeDNS())
        #expect(await logos.logo(for: "someone@icloud.com") == nil)
        #expect(site.urls.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func png(side: Int) -> Data {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

private final class Clock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { date.withLock { $0 } }
    func advance(by seconds: TimeInterval) { date.withLock { $0.addTimeInterval(seconds) } }
}

private final class FakeSite: HTTPClient {
    private let image: Data
    private let requested = Mutex<[String]>([])

    init(image: Data) {
        self.image = image
    }

    var urls: [String] { requested.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requested.withLock { $0.append(request.url!.absoluteString) }
        return (image, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private final class FakeDNS: TXTResolving {
    private let records: [String: [String]]
    private let asked = Mutex<[String]>([])

    init(_ records: [String: [String]] = [:]) {
        self.records = records
    }

    var names: [String] { asked.withLock { $0 } }

    func txtRecords(named name: String) async -> [String] {
        asked.withLock { $0.append(name) }
        return records[name] ?? []
    }
}
