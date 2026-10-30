import Testing
@testable import widgets

struct PassphraseFormatStyleTests {
    @Test(arguments: [
        (" TrEzOr ", "␣TrEzOr␣"),
        ("TrEzOr", "TrEzOr"),
        ("   ", "␣␣␣"),
        ("my secret  phrase", "my secret  phrase"),
        ("\u{3000}TrEzOr\u{A0}", "␣TrEzOr␣"),
    ])
    func `Only spaces at the start and end of a passphrase show as marks`(passphrase: String, shown: String) {
        #expect(PassphraseFormatStyle.passphrase.format(passphrase) == shown)
    }
}
