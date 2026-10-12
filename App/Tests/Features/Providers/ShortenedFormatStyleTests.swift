import Testing
@testable import widgets

/// Verifies that text which can be a key shows only enough to recognize it.
struct ShortenedFormatStyleTests {
    /// Text longer than four characters shows only its first four; shorter text stays as it is.
    /// - Parameters:
    ///   - text: The full text.
    ///   - shown: The text as people see it.
    @Test(arguments: [
        ("", ""),
        ("abcd", "abcd"),
        ("abcde", "abcd…"),
        ("a1b2c3d4-e5f6-7890-abcd-ef1234567890", "a1b2…"),
    ])
    func `Only the first four characters of longer text show`(text: String, shown: String) {
        #expect(ShortenedFormatStyle.shortened.format(text) == shown)
    }
}
