import Testing
@testable import widgets

/// Verifies that a saved key's preview shows only its first characters and masks the rest.
struct KeyPreviewFormatStyleTests {
    /// Each character after the first four shows as a dot, and a preview formats the same as its key.
    /// - Parameters:
    ///   - key: The key, or a preview of it.
    ///   - shown: The preview the details show.
    @Test(arguments: [
        ("fixture-key", "fixt•••••••"),
        ("fixt•••••••", "fixt•••••••"),
        ("fix", "fix"),
    ])
    func `Only the first four characters of a key show`(key: String, shown: String) {
        #expect(KeyPreviewFormatStyle.keyPreview.format(key) == shown)
        #expect(KeyPreviewFormatStyle.keyStart.format(key) == String(shown.prefix(4)))
    }
}
