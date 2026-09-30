import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

/// Synchronous file work confined to one coordinated operation.
enum PackageFiles {
    /// Reads a package and owns all declared image bytes before returning.
    /// - Parameter url: The coordinated directory URL.
    /// - Returns: A fully validated independent snapshot.
    /// - Throws: A validation, file-system, or cancellation error.
    static func read(at url: URL) throws -> Pack {
        let directory = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) } ?? -1
        }
        guard directory >= 0 else {
            throw ValidationError(path: "package", reason: "Expected a readable directory; symbolic links are unsupported.")
        }
        defer { close(directory) }
        let manifest = try Manifest.decode(readFile(["manifest.json"], in: directory, path: "manifest.json"))
        var assets: [String: Asset] = [:]
        for name in manifest.assets.keys.sorted() {
            try Task.checkCancellation()
            guard let path = manifest.assets[name] else { continue }
            let components = try assetComponents(path, field: "assets.\(name)")
            let data = try readFile(components, in: directory, path: path)
            try validateImage(data, path: path)
            assets[name] = Asset(data: data, path: path)
        }
        try Task.checkCancellation()
        return Pack(manifest: manifest, assets: assets)
    }

    /// Builds a fresh package, retaining only declared assets.
    /// - Parameters:
    ///   - manifest: Complete export metadata and colors.
    ///   - assets: Previously validated image snapshots.
    /// - Returns: A wrapper confined to the current export operation.
    /// - Throws: A serialization, path, or cancellation error.
    static func wrapper(manifest: Manifest, assets: [String: Asset]) throws -> FileWrapper {
        let root = FileWrapper(directoryWithFileWrappers: ["manifest.json": FileWrapper(regularFileWithContents: try manifest.encode())])
        for name in assets.keys.sorted() {
            try Task.checkCancellation()
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
    /// - Returns: Owned file bytes.
    /// - Throws: A validation or cooperative cancellation error.
    private static func readFile(_ components: [String], in root: Int32, path: String) throws -> Data {
        let failure = ValidationError(path: path, reason: "Expected a readable regular file inside the package; symbolic links are unsupported.")
        var directory = root
        defer { if directory != root { close(directory) } }
        for component in components.dropLast() {
            try Task.checkCancellation()
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
        var data = Data()
        do {
            while true {
                try Task.checkCancellation()
                guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw failure
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
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1,
                kCGImageSourceShouldCache: false
              ] as CFDictionary) != nil else {
            throw ValidationError(path: path, reason: "Expected a readable PNG or JPEG image.")
        }
    }
}
