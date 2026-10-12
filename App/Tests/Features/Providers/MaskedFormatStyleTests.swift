import Testing
@testable import widgets

/// Verifies that text which can be a key shows only enough to recognize it.
struct MaskedFormatStyleTests {
    /// Each character after the first four shows as a dot; shorter text stays as it is, and masked text formats the
    /// same again.
    /// - Parameters:
    ///   - text: The full text.
    ///   - shown: The text as people see it.
    @Test(arguments: [
        ("", ""),
        ("abcd", "abcd"),
        ("abcde", "abcd•"),
        ("fixture-key", "fixt•••••••"),
        ("fixt•••••••", "fixt•••••••"),
    ])
    func `Only the first four characters of longer text show`(text: String, shown: String) {
        #expect(MaskedFormatStyle.masked.format(text) == shown)
    }
}
