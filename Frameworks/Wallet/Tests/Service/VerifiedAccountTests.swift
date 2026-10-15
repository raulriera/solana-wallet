import Testing
@testable import Wallet

/// Verifies the recovered-account check that signing and private-balance keys share.
struct VerifiedAccountTests {
    /// The error each check throws for a mismatch.
    private enum CheckError: Error {
        /// The address is malformed or belongs to another account.
        case mismatch
    }

    /// Verifies that the expected account's work receives the phrase's BIP-39 seed.
    ///
    /// The seed is the first published BIP-39 vector, for the public phrase with the passphrase
    /// `TREZOR`; the address is its independently derived account at `m/44'/501'/0'/0'`.
    @Test
    func `The expected account receives its seed`() throws {
        let vector = try #require(BIP39Vector.examples().first)

        let seed = try Wallet.withVerifiedAccount(
            PublicRecovery.phrase(), passphrase: "TREZOR", path: .solana,
            expectedAddress: "7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe", mismatch: CheckError.mismatch
        ) { _, seed in seed }

        #expect(seed == (try fixtureBytes(vector.seed)))
    }

    /// Verifies that another account or a malformed address throws the supplied error without
    /// running the work.
    ///
    /// - Parameters:
    ///   - address: An address that the phrase, passphrase, and `m/44'/501'/0'/0'` don't derive.
    ///   - passphrase: The BIP-39 passphrase.
    @Test(arguments: [
        (PublicRecovery.addresses[0], "TREZOR"),
        (PublicRecovery.addresses[1], ""),
        ("HAgk14JpMQLgt6rVgv7cBQFJ", ""),
    ])
    func `Another account or a malformed address throws the supplied error`(address: String, passphrase: String) throws {
        let recovery = try PublicRecovery.phrase()

        #expect(throws: CheckError.mismatch) {
            try Wallet.withVerifiedAccount(
                recovery, passphrase: passphrase, path: .solana,
                expectedAddress: address, mismatch: CheckError.mismatch
            ) { _, _ in Issue.record("The work ran for another account.") }
        }
    }
}
