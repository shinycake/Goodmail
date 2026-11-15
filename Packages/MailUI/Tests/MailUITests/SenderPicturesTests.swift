import Synchronization
import Testing
import UIKit

@testable import MailUI

@MainActor
struct SenderPicturesTests {
    private static let png = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).pngData { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    }

    @Test func aDomainIsLoadedOnceForEverySenderAtItAndDecodedSmall() async throws {
        let asked = Mutex<[String]>([])
        let png = Self.png
        let pictures = SenderPictures(scale: 2) { address in
            asked.withLock { $0.append(address) }
            return png
        }
        guard case .unknown = pictures.lookup(for: "a@paypal.com") else {
            Issue.record("A picture nobody asked for is unknown")
            return
        }

        async let first = pictures.picture(for: "a@paypal.com")
        async let second = pictures.picture(for: "b@paypal.com")
        let images = await [first, second]

        #expect(asked.withLock { $0.count } == 1)
        let image = try #require(images[0])
        #expect(max(image.size.width, image.size.height) * image.scale <= SenderPictures.side * 2)
        guard case .picture = pictures.lookup(for: "c@paypal.com") else {
            Issue.record("A loaded domain's picture is known at once")
            return
        }
    }

    @Test func publicMailAndMissingPicturesShowInitials() async {
        let pictures = SenderPictures(scale: 2) { _ in nil }
        guard case .none = pictures.lookup(for: "someone@gmail.com") else {
            Issue.record("Public mail has no brand picture")
            return
        }
        #expect(await pictures.picture(for: "a@example.com") == nil)
        guard case .none = pictures.lookup(for: "a@example.com") else {
            Issue.record("A domain without a picture is remembered")
            return
        }
    }
}
