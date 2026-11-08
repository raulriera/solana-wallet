public import Foundation

/// A type that reads and saves packs and exports templates.
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

    /// Exports default tokens as a new theme with a new identifier.
    ///
    /// - Parameters:
    ///   - name: A nonempty display name for the theme.
    ///   - defaults: The complete default tokens.
    ///   - url: The destination package URL.
    /// - Throws: A validation, file-access, or cancellation error.
    func exportTemplate(named name: String, defaults: Tokens, to url: URL) async throws
}
