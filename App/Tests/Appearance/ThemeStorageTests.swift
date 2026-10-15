import Foundation
import Testing
@testable import widgets

/// Verifies the checks that the theme catalog and the preferences store share for their folder and bundled themes.
struct ThemeStorageTests {
    /// Verifies that a location outside the file system is refused.
    /// - Throws: An error if the fixture URL is invalid.
    @Test
    func `Storage outside the file system is refused`() throws {
        let location = try #require(URL(string: "https://example.com/Themes"))

        #expect(throws: ThemeCatalogError.invalidStorage) { try ThemeStorage(directory: location, builtIns: []) }
    }

    /// Verifies that two bundled themes with one identity are refused.
    @Test
    func `Bundled themes that share an identity are refused`() {
        let id = UUID()
        let themes = [BundledTheme(id: id, name: "First", url: URL.temporaryDirectory),
                      BundledTheme(id: id, name: "Second", url: URL.temporaryDirectory)]

        #expect(throws: ThemeCatalogError.duplicateBuiltIn) {
            try ThemeStorage(directory: URL.temporaryDirectory, builtIns: themes)
        }
    }

    /// Verifies that bundled themes are keyed by identity, along with their catalog entries.
    /// - Throws: An error if the storage is refused.
    @Test
    func `Bundled themes are keyed by identity with their catalog entries`() throws {
        let theme = BundledTheme(id: UUID(), name: "Original", url: URL.temporaryDirectory)

        let storage = try ThemeStorage(directory: URL.temporaryDirectory, builtIns: [theme])

        #expect(storage.builtIns[theme.entry.id]?.url == theme.url)
        #expect(storage.builtInEntries == [theme.entry.id: theme.entry])
    }
}
