import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

/// Synchronous file work confined to one coordinated operation.
enum PackageFiles {
    /// Reads a package and owns all declared image bytes before returning.
    /// - Parameters:
    ///   - url: The coordinated directory URL.
    ///   - checkCancellation: Checks cancellation on the background file queue.
    ///   - manifestByteBudget: The allowance for both input and complete exported JSON.
    ///   - assetByteBudget: The aggregate allowance for unique image files.
    /// - Returns: A fully validated independent snapshot.
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

    /// Reserves room for complete export values so every accepted pack can be read back after export.
    /// - Parameters:
    ///   - manifest: The decoded overrides and metadata.
    ///   - byteLimit: The allowance for complete exported JSON.
    /// - Throws: A validation error if a complete manifest would exceed the read budget.
    private static func validateExportSize(_ manifest: Manifest, byteLimit: Int) throws {
        let longest = Color.System.allCases.max { $0.rawValue.utf8.count < $1.rawValue.utf8.count }!
        let complete = Dictionary(uniqueKeysWithValues: Appearance.allCases.map { appearance in
            (appearance, Dictionary(uniqueKeysWithValues: Role.allCases.map { role in
                (role, manifest.colors[appearance]?[role] ?? .system(longest))
            }))
        })
        let exported = Manifest(id: manifest.id, name: manifest.name, colors: complete, assets: manifest.assets)
        try ResourceLimits.checkBytes(Int64(try exported.encode().count), limit: byteLimit, path: "manifest.json")
    }

    /// Builds a fresh package, retaining only declared assets.
    /// - Parameters:
    ///   - manifest: Validated metadata and color settings, preserving omissions when installing.
    ///   - assets: Previously validated image snapshots.
    ///   - checkCancellation: Checks cancellation on the background file queue.
    /// - Returns: A wrapper confined to the current export operation.
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

    /// Restricts image paths to descendants of the Assets directory.
    /// - Parameters:
    ///   - path: A package-relative declaration.
    ///   - field: Its manifest field path.
    /// - Returns: Safe literal path components.
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

    /// Opens each component relative to its directory without following symbolic links.
    ///
    /// Descriptor-relative access prevents a checked directory from being replaced by a link
    /// before its file is opened. Nonblocking open and fstat also reject special files safely.
    /// - Parameters:
    ///   - components: Validated relative path components.
    ///   - root: An open package directory descriptor owned by the caller.
    ///   - path: The author-facing package location.
    ///   - byteLimit: The smaller of the file limit and remaining package allowance.
    ///   - checkCancellation: Checks cancellation on the background file queue.
    /// - Returns: Owned file bytes.
    /// - Throws: A validation or cooperative cancellation error.
    private static func readFile(_ components: [String], in root: Int32, path: String, byteLimit: Int,
                                 checkCancellation: () throws -> Void) throws -> Data {
        let failure = ValidationError(path: path, reason: "Expected a readable regular file inside the package; symbolic links are unsupported.")
        var directory = root
        defer { if directory != root { close(directory) } }
        for component in components.dropLast() {
            try checkCancellation()
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw failure }
            if directory != root { close(directory) }
            directory = next
        }
        guard let filename = components.last else { throw failure }
        let descriptor = openat(directory, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { throw failure }
        try ResourceLimits.checkBytes(attributes.st_size, limit: byteLimit, path: path)
        var data = Data()
        data.reserveCapacity(Int(attributes.st_size))
        while true {
            try checkCancellation()
            let chunk: Data
            do {
                chunk = try autoreleasepool { try handle.read(upToCount: min(65_536, byteLimit - data.count + 1)) ?? Data() }
            } catch {
                throw failure
            }
            if chunk.isEmpty { break }
            // Recheck actual bytes: another process need not honor coordination or the earlier size.
            try ResourceLimits.checkBytes(Int64(data.count + chunk.count), limit: byteLimit, path: path)
            data.append(chunk)
        }
        return data
    }

    /// Confirms the actual image format and decodability without retaining a full-size bitmap.
    /// - Parameters:
    ///   - data: Owned image bytes.
    ///   - path: Their package-relative location.
    /// - Throws: A validation error for unsupported or incomplete image data.
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
