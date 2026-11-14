import Foundation
import ImageIO
import MailCore
import Synchronization
import Testing
import UniformTypeIdentifiers

@testable import MailNotifications

struct SenderLogosTests {
    @Test(arguments: [
        ("noreply@mail.github.com", "github.com"),
        ("billing@Example.CO.IL", "example.co.il"),
        ("news@shop.example.com.au", "example.com.au"),
        ("someone@gmail.com", nil),
        ("friend@walla.co.il", nil),
        ("broken", nil),
        ("x@localhost", nil),
        ("x@exa mple.com", nil),
    ])
    func logosComeFromTheRegistrableDomainOfNonFreeMail(address: String, domain: String?) {
        #expect(SenderLogos.domain(for: address) == domain)
    }

    @Test func aFetchedLogoIsCachedForAMonth() async throws {
        let site = FakeSite(image: png(side: 120))
        let clock = Clock()
        let logos = SenderLogos(directory: try temporaryDirectory(), http: site, now: { clock.now })

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
        let logos = SenderLogos(directory: try temporaryDirectory(), http: site, now: { clock.now })

        #expect(await logos.logo(for: "a@example.com") == nil)
        #expect(await logos.logo(for: "a@example.com") == nil)
        #expect(site.urls.count == 1)
        clock.advance(by: 8 * 86_400)
        _ = await logos.logo(for: "a@example.com")
        #expect(site.urls.count == 2)
    }

    @Test func freeMailIsNeverLookedUp() async throws {
        let site = FakeSite(image: png(side: 120))
        let logos = SenderLogos(directory: try temporaryDirectory(), http: site)
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
