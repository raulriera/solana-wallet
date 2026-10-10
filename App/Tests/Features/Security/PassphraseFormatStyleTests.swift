import Testing
@testable import widgets

/// Verifies that the recovery backup keeps a passphrase's edge spaces noticeable, since they change the wallet.
struct PassphraseFormatStyleTests {
    /// Each space at the start or end shows as a mark; inner spaces stay as typed.
    /// - Parameters:
    ///   - passphrase: The passphrase as typed during import.
    ///   - shown: What the backup shows.
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
