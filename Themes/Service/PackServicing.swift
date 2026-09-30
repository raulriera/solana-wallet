public import Foundation

/// Reads, saves, resolves, and exports packages without owning app preferences or a catalog.
public protocol PackServicing: Sendable {
    /// Loads and validates a directory package, including every declared image.
    /// - Parameter url: A local or security-scoped package directory URL.
    /// - Returns: A snapshot independent of the original files and their access lifetime.
    /// - Throws: A validation, file-access, or cancellation error.
    func read(from url: URL) async throws -> Pack

    /// Saves an owned snapshot for installation, preserving omitted color overrides.
    /// - Parameters:
    ///   - pack: A validated snapshot independent of its source files.
    ///   - url: The app-owned destination package directory.
    /// - Throws: A file-access or pre-commit cancellation error.
    func save(_ pack: Pack, to url: URL) async throws

    /// Fills omitted color settings from the matching app-provided appearance.
    /// - Parameters:
    ///   - pack: A validated imported pack.
    ///   - defaults: Complete app-owned palettes.
    /// - Returns: Complete colors with system references preserved.
    func resolve(_ pack: Pack, defaults: Colors) -> Colors

    /// Exports a complete custom theme while preserving its identity and assets.
    ///
    /// The caller owns destination selection and replacement approval. Cancellation is
    /// checked before the atomic write begins; a committed write completes successfully.
    /// - Parameters:
    ///   - pack: The validated source snapshot.
    ///   - defaults: Defaults used to fill omitted settings.
    ///   - url: The destination package URL.
    /// - Throws: A file-access or pre-commit cancellation error.
    func export(_ pack: Pack, defaults: Colors, to url: URL) async throws

    /// Exports complete defaults as a new custom theme with a freshly generated UUID.
    /// - Parameters:
    ///   - name: A nonempty display name for the template.
    ///   - defaults: Complete app-owned palettes.
    ///   - url: The destination package URL, with replacement approved by the caller.
    /// - Throws: A validation, file-access, or pre-commit cancellation error.
    func exportTemplate(named name: String, defaults: Colors, to url: URL) async throws
}
