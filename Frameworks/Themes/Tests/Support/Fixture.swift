import Foundation
import CoreGraphics
import ImageIO
import Testing
import Themes

struct Fixture {
    let directory: URL
    let source: URL
    static let id = UUID(uuidString: "A416C5BC-E1F3-4614-929A-CEF0B40AF7D0")!
    static let header = #""version":1,"id":"\#(id.uuidString)","name":"Example""#
    static let defaults = Colors(light: palette(.system(.systemBackground)),
                                 dark: palette(.system(.label)),
                                 lightIncreasedContrast: palette(.system(.white)),
                                 darkIncreasedContrast: palette(.system(.black)))

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        source = directory.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func manifest(_ fields: String = "") throws {
        try rawManifest("{\(Self.header)\(fields.isEmpty ? "" : ",\(fields)")}")
    }

    func rawManifest(_ json: String) throws {
        try Data(json.utf8).write(to: source.appendingPathComponent("manifest.json"))
    }

    func asset(_ data: Data, path: String = "Assets/image.png") throws {
        let url = source.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    static func palette(_ color: Themes.Color) -> Palette {
        Palette(background: color, surface: color, primaryText: color, secondaryText: color,
                separator: color, accent: color, onAccent: color)
    }

    static func image(type: String = "public.png", width: Int = 2, height: Int = 2) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func exportedJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
