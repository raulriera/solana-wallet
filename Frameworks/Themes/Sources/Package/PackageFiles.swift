import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

/// A namespace for reading and building theme package files.
enum PackageFiles {
    /// Reads and validates a package and its declared images.
    ///
    /// - Parameters:
    ///   - url: The coordinated directory URL.
    ///   - checkCancellation: A closure that throws if the operation was cancelled.
    ///   - manifestByteBudget: The byte limit for the manifest and its complete export.
    ///   - assetByteBudget: The total byte limit for unique image files.
    /// - Returns: The validated pack.
    /// - Throws: A validation, file-system, or cancellation error.
    static func read(at url: URL, checkCancellation: () throws -> Void,
                     manifestByteBudget: Int = ResourceLimits.manifestBytes,
                     assetByteBudget: Int = ResourceLimits.totalAssetBytes) throws -> Pack {
        let directory = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) } ?? -1
        }
        guard directory >= 0 else {
            throw ValidationError(path: "package", reason: "Expected a readable directory; symbolic links are unsupported.")
        }
        defer { close(directory) }
        let manifest = try Manifest.decode(readFile(["manifest.json"], in: directory, path: "manifest.json",
                                                   byteLimit: manifestByteBudget, checkCancellation: checkCancellation))
        try validateExportSize(manifest, byteLimit: manifestByteBudget)
        var assets: [String: Asset] = [:]
        var files: [String: Asset] = [:]
        var remainingBytes = assetByteBudget
        for name in manifest.assets.keys.sorted() {
            try checkCancellation()
            guard let path = manifest.assets[name] else { continue }
            if let existing = files[path] {
                assets[name] = existing
                continue
            }
            let components = try assetComponents(path, field: "assets.\(name)")
            let asset = try autoreleasepool {
                let data = try readFile(components, in: directory, path: path,
                                        byteLimit: min(ResourceLimits.assetBytes, remainingBytes),
                                        checkCancellation: checkCancellation)
                try checkCancellation()
                try validateImage(data, path: path)
                return Asset(data: data, path: path)
            }
            remainingBytes -= asset.data.count
            files[path] = asset
            assets[name] = asset
        }
        try checkCancellation()
        return Pack(manifest: manifest, assets: assets)
    }

    /// Throws if the manifest, with every color filled, would exceed a byte limit.
    ///
    /// - Parameters:
    ///   - manifest: The decoded manifest.
    ///   - byteLimit: The byte limit for the complete manifest.
    /// - Throws: A validation error if the complete manifest exceeds the limit.
    private static func validateExportSize(_ manifest: Manifest, byteLimit: Int) throws {
        // swift-format-ignore: NeverForceUnwrap
        let longest = Color.System.allCases.max { $0.rawValue.utf8.count < $1.rawValue.utf8.count }!
        let complete = Dictionary(uniqueKeysWithValues: Appearance.allCases.map { appearance in
            (appearance, Dictionary(uniqueKeysWithValues: Role.allCases.map { role in
                (role, manifest.colors[appearance]?[role] ?? .system(longest))
            }))
        })
        let exported = Manifest(id: manifest.id, name: manifest.name, colors: complete, assets: manifest.assets)
        try ResourceLimits.checkBytes(Int64(try exported.encode().count), limit: byteLimit, path: "manifest.json")
    }

    /// Builds a package's file wrapper.
    ///
    /// - Parameters:
    ///   - manifest: The validated manifest.
    ///   - assets: The validated assets, keyed by declaration name.
    ///   - checkCancellation: A closure that throws if the operation was cancelled.
    /// - Returns: The package's directory wrapper.
    /// - Throws: A serialization, path, or cancellation error.
    static func wrapper(manifest: Manifest, assets: [String: Asset], checkCancellation: () throws -> Void) throws -> FileWrapper {
        let encoded = try manifest.encode()
        try ResourceLimits.checkBytes(Int64(encoded.count), limit: ResourceLimits.manifestBytes, path: "manifest.json")
        let root = FileWrapper(directoryWithFileWrappers: ["manifest.json": FileWrapper(regularFileWithContents: encoded)])
        for name in assets.keys.sorted() {
            try checkCancellation()
            guard let asset = assets[name] else { continue }
            let components = try assetComponents(asset.path, field: "assets.\(name)")
            var directory = root
            for component in components.dropLast() {
                if let existing = directory.fileWrappers?[component] {
                    directory = existing
                } else {
                    let child = FileWrapper(directoryWithFileWrappers: [:])
                    child.preferredFilename = component
                    directory.addFileWrapper(child)
                    directory = child
                }
            }
            if let filename = components.last, directory.fileWrappers?[filename] == nil {
                let file = FileWrapper(regularFileWithContents: asset.data)
                file.preferredFilename = filename
                directory.addFileWrapper(file)
            }
        }
        return root
    }

    /// Splits an image path inside the Assets directory into its components.
    ///
    /// - Parameters:
    ///   - path: The package-relative image path.
    ///   - field: The manifest field that declares the path.
    /// - Returns: The path's components.
    /// - Throws: A validation error for absolute, escaping, or ambiguous paths.
    private static func assetComponents(_ path: String, field: String) throws -> [String] {
        let components = path.components(separatedBy: "/")
        guard components.count > 1, components.first == "Assets",
              !path.contains("\\"), !path.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ValidationError(path: field, reason: "Expected a relative file path inside Assets without traversal.")
        }
        return components
    }

    /// Reads a regular file in the package without following symbolic links.
    ///
    /// - Parameters:
    ///   - components: Validated relative path components.
    ///   - root: The open package directory's descriptor.
    ///   - path: The file's package-relative path.
    ///   - byteLimit: The maximum number of bytes to read.
    ///   - checkCancellation: A closure that throws if the operation was cancelled.
    /// - Returns: The file's bytes.
    /// - Throws: A validation or cancellation error.
    private static func readFile(_ components: [String], in root: Int32, path: String, byteLimit: Int,
                                 checkCancellation: () throws -> Void) throws -> Data {
        let unreadable = ValidationError(path: path, reason: "Expected a readable regular file inside the package; symbolic links are unsupported.")
        var directory = root
        defer { if directory != root { close(directory) } }
        for component in components.dropLast() {
            try checkCancellation()
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw unreadable }
            if directory != root { close(directory) }
            directory = next
        }
        guard let filename = components.last else { throw unreadable }
        let descriptor = openat(directory, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw unreadable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { throw unreadable }
        try ResourceLimits.checkBytes(attributes.st_size, limit: byteLimit, path: path)
        var data = Data()
        data.reserveCapacity(Int(attributes.st_size))
        while true {
            try checkCancellation()
            let chunk: Data
            do {
                chunk = try autoreleasepool { try handle.read(upToCount: min(65_536, byteLimit - data.count + 1)) ?? Data() }
            } catch {
                throw unreadable
            }
            if chunk.isEmpty { break }
            try ResourceLimits.checkBytes(Int64(data.count + chunk.count), limit: byteLimit, path: path)
            data.append(chunk)
        }
        return data
    }

    /// Throws unless data is a decodable PNG or JPEG image within the pixel limit.
    ///
    /// - Parameters:
    ///   - data: The image bytes.
    ///   - path: The image's package-relative path.
    /// - Throws: A validation error for unsupported, oversized, or incomplete image data.
    private static func validateImage(_ data: Data, path: String) throws {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw ValidationError(path: path, reason: "Expected a readable PNG or JPEG image.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
        guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= ResourceLimits.imagePixels / height else {
            throw ValidationError(path: path, reason: "Image exceeds the \(ResourceLimits.imagePixels)-pixel limit or has invalid dimensions.")
        }
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1,
                kCGImageSourceShouldCache: false
              ] as CFDictionary) != nil else {
            throw ValidationError(path: path, reason: "Expected a readable PNG or JPEG image.")
        }
    }
}
