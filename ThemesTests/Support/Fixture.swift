import Foundation
import CoreGraphics
import ImageIO
import Testing
import Themes

/// A separate temporary directory for each test invocation.
struct Fixture {
    let directory: URL
    let source: URL
    static let id = UUID(uuidString: "A416C5BC-E1F3-4614-929A-CEF0B40AF7D0")!
    static let header = "\"version\":1,\"id\":\"\(id.uuidString)\",\"name\":\"Example\""
    static let defaults = Colors(light: palette(.system(.systemBackground)),
                                 dark: palette(.system(.label)),
                                 lightIncreasedContrast: palette(.system(.white)),
                                 darkIncreasedContrast: palette(.system(.black)))

    /// Creates a unique test directory with an empty package.
    /// - Throws: A file-system error.
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        source = directory.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }

    /// Deletes only this fixture's temporary directory.
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Writes a manifest containing the standard header and optional additional fields.
    /// - Parameter fields: Additional raw JSON fields without outer braces.
    /// - Throws: A file-system error.
    func manifest(_ fields: String = "") throws {
        try rawManifest("{\(Self.header)\(fields.isEmpty ? "" : ",\(fields)")}")
    }

    /// Writes raw JSON to exercise malformed manifests.
    /// - Parameter json: The complete manifest text.
    /// - Throws: A file-system error.
    func rawManifest(_ json: String) throws {
        try Data(json.utf8).write(to: source.appendingPathComponent("manifest.json"))
    }

    /// Writes test image bytes into a relative package path.
    /// - Parameters:
    ///   - data: The fixture bytes.
    ///   - path: A relative path created inside the source package.
    /// - Throws: A file-system error.
    func asset(_ data: Data, path: String = "Assets/image.png") throws {
        let url = source.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Builds a synthetic palette whose roles are identical for simple fallback assertions.
    /// - Parameter color: The test color used for every role.
    /// - Returns: A complete fixture palette, unrelated to production appearance defaults.
    static func palette(_ color: Themes.Color) -> Palette {
        Palette(background: color, surface: color, primaryText: color, secondaryText: color,
                separator: color, accent: color, onAccent: color)
    }

    /// Creates a real small image fixture using the platform encoder.
    /// - Parameters:
    ///   - type: A supported ImageIO destination type identifier.
    ///   - width: The image width used to exercise decoding resource limits.
    ///   - height: The image height used to exercise decoding resource limits.
    /// - Returns: Encoded image bytes.
    /// - Throws: A failed fixture precondition.
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

    /// Reads exported JSON independently of the service decoder.
    /// - Parameter url: An exported package directory.
    /// - Returns: Its JSON object for structural assertions.
    /// - Throws: A read, parsing, or fixture-precondition error.
    static func exportedJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
