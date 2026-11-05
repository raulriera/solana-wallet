import Testing
@testable import widgets

struct MaskedFormatStyleTests {
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
