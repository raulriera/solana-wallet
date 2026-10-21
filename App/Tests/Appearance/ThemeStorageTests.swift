import Foundation
import Testing
@testable import widgets

/// Verifies the folder and bundled themes that the theme catalog and the preferences store share.
struct ThemeStorageTests {
    /// Verifies that bundled themes are keyed by identity, along with their catalog entries.
    @Test
    func `Bundled themes are keyed by identity with their catalog entries`() {
        let theme = BundledTheme(id: UUID(), name: "Original", url: URL.temporaryDirectory)

        let storage = ThemeStorage(directory: URL.temporaryDirectory, builtIns: [theme])

        #expect(storage.builtIns[theme.entry.id]?.url == theme.url)
        #expect(storage.builtInEntries == [theme.entry.id: theme.entry])
    }
}
