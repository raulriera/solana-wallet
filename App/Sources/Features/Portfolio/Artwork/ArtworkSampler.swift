import CoreGraphics
import Foundation
import ImageIO

/// Picks a logo's most common colored region from a small thumbnail.
nonisolated enum ArtworkSampler {
    /// Samples encoded image data without decoding it at full size.
    ///
    /// Transparent and neutral pixels, such as backgrounds and borders, don't count.
    /// - Parameter data: The encoded logo, such as PNG or JPEG data.
    /// - Returns: The average color of the most common colored region, or `nil` when the data isn't an image
    ///   or has no colored pixels.
    static func color(from data: Data) -> ArtworkColor? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 32,
              ] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                          | CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var regions: [Int: (count: Double, red: Double, green: Double, blue: Double)] = [:]
        for index in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let red = min(255, Double(pixels[index]) / alpha)
            let green = min(255, Double(pixels[index + 1]) / alpha)
            let blue = min(255, Double(pixels[index + 2]) / alpha)
            guard max(red, green, blue) - min(red, green, blue) > 24 else { continue }
            let key = (Int(red) / 32) << 6 | (Int(green) / 32) << 3 | Int(blue) / 32
            var region = regions[key, default: (0, 0, 0, 0)]
            region.count += 1
            region.red += red
            region.green += green
            region.blue += blue
            regions[key] = region
        }
        // Equal regions fall to the lower key, so a logo always gives the same color.
        guard let winner = regions.max(by: { lhs, rhs in
            lhs.value.count == rhs.value.count ? lhs.key > rhs.key : lhs.value.count < rhs.value.count
        })?.value else { return nil }
        let scale = winner.count * 255
        return ArtworkColor(red: winner.red / scale, green: winner.green / scale, blue: winner.blue / scale)
    }
}
