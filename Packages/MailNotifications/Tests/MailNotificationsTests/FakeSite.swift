import Foundation
import ImageIO
import MailCore
import Synchronization
import UniformTypeIdentifiers

/// A web server that answers every request with one image, and remembers what was asked.
final class FakeSite: HTTPClient {
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

    /// A square of one color, `side` pixels wide.
    static func png(side: Int) -> Data {
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
