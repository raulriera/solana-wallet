import Testing
@testable import Wallet

struct VerifiedAccountTests {
    private enum CheckError: Error {
        case mismatch
    }

    @Test
    func `The expected account receives its seed`() throws {
        let vector = try #require(BIP39Vector.examples().first)

        let seed = try Wallet.withVerifiedAccount(
            PublicRecovery.phrase(), passphrase: "TREZOR", path: .solana,
            expectedAddress: "7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe", mismatch: CheckError.mismatch
        ) { _, seed in seed }

        #expect(seed == (try fixtureBytes(vector.seed)))
    }

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
