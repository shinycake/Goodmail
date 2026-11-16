import CoreGraphics
import Foundation

/// An RGBA bitmap to draw into and read back, eight bits a channel with alpha premultiplied. Core Graphics allocates
/// and frees its pixels, so no pointer to them leaves Core Graphics.
nonisolated struct RGBABitmap {
    let width: Int
    let height: Int
    let context: CGContext

    init?(width: Int, height: Int) {
        guard width > 0, height > 0,
            // Unsafe because the initializer takes a pointer to the pixels. Safe: it's nil, so Core Graphics
            // allocates them and keeps them for as long as the context lives.
            let context = unsafe CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        (self.width, self.height, self.context) = (width, height, context)
    }

    /// What's drawn so far, four bytes a pixel (red, green, blue, alpha), top row first, rows packed.
    var pixels: [UInt8]? {
        guard let image = context.makeImage(), let data = image.dataProvider?.data as Data? else { return nil }
        let row = width * 4
        var pixels: [UInt8] = []
        pixels.reserveCapacity(row * height)
        for y in 0..<height {
            let start = data.startIndex + y * image.bytesPerRow
            pixels += data[start..<start + row]
        }
        return pixels
    }
}
