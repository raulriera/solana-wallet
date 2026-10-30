public import Foundation

/// A type that reads, saves, and resolves packs and exports templates.
public protocol PackServicing: Sendable {
    /// Loads and validates a directory package, including every declared image.
    ///
    /// - Parameter url: A local or security-scoped package directory URL.
    /// - Returns: The validated pack.
    /// - Throws: A validation, file-access, or cancellation error.
    func read(from url: URL) async throws -> Pack

    /// Saves a pack to a package directory without filling its omitted colors.
    ///
    /// - Parameters:
    ///   - pack: The validated pack.
    ///   - url: The destination package directory.
    /// - Throws: A file-access or cancellation error.
    func save(_ pack: Pack, to url: URL) async throws

    /// Fills a pack's omitted colors from default palettes.
    ///
    /// - Parameters:
    ///   - pack: A validated pack.
    ///   - defaults: The complete default palettes.
    /// - Returns: The complete colors.
    func resolve(_ pack: Pack, defaults: Colors) -> Colors

    /// Exports default palettes as a new theme with a new identifier.
    ///
    /// - Parameters:
    ///   - name: A nonempty display name for the theme.
    ///   - defaults: The complete default palettes.
    ///   - url: The destination package URL.
    /// - Throws: A validation, file-access, or cancellation error.
    func exportTemplate(named name: String, defaults: Colors, to url: URL) async throws
}
