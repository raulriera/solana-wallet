import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Generated logos for artwork sampling, encoded as PNG data.
enum ArtworkFixture {
    /// Encodes a square logo with a filled center inside a gray border.
    /// - Parameters:
    ///   - border: The gray level of the border and background, from 0 to 1.
    ///   - center: The sRGB components of the logo's center, from 0 to 1.
    /// - Returns: The encoded PNG data.
    /// - Throws: A test prerequisite error if the logo can't be drawn or encoded.
    static func png(border: CGFloat = 1, center: (red: CGFloat, green: CGFloat, blue: CGFloat)) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [border, border, border, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [center.red, center.green, center.blue, 1])))
        context.fill(CGRect(x: 20, y: 20, width: 24, height: 24))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
