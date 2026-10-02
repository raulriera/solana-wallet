import Testing
import Wallet

/// Tests the wallet through its public API without privileged access or networking.
struct WalletTests {
    /// Verifies recovery across paths and significant or Unicode-normalized passphrases.
    ///
    /// Expected addresses were derived independently with Python hashlib/HMAC and OpenSSL Ed25519.
    ///
    /// - Parameters:
    ///   - path: The explicit Solana account path.
    ///   - passphrase: The BIP-39 passphrase, including significant whitespace.
    ///   - expected: The independently derived Solana address.
    @Test(arguments: [
        ("m/44'/501'/0'/0'", "", "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"),
        ("m/44'/501'/1'/0'", "", "Hh8QwFUA6MtVu1qAoq12ucvFHNwCcVTV7hpWjeY1Hztb"),
        ("m/44'/501'/0'", "", "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL"),
        ("m/44'/501'/0'/0'", "TREZOR", "7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe"),
        ("m/44'/501'/0'/0'", "café", "56u4aAiTCjGEcS4ksrFcqS3nxsRSmzkE3MiFHzY85ngF"),
        ("m/44'/501'/0'/0'", "cafe\u{301}", "56u4aAiTCjGEcS4ksrFcqS3nxsRSmzkE3MiFHzY85ngF"),
        ("m/44'/501'/0'/0'", " TREZOR ", "SbBZ94nCjPnE1w7BYq86Dn7cjHar2z6RC7Ni39t2aK4"),
    ])
    func `Imported recovery phrases derive expected Solana addresses`(path: String, passphrase: String, expected: String) async throws {
        let wallet: any WalletProviding = Wallet()
        let phrase = try RecoveryPhrase("  " + Array(repeating: "ABANDON", count: 11).joined(separator: " \n\t") + " ABOUT  ")

        let address = try await wallet.address(for: phrase, passphrase: passphrase, path: DerivationPath(path))

        #expect(address == expected)
    }

    /// Verifies that a newly generated twelve-word wallet restores the same default account.
    @Test
    func `New twelve-word wallets restore their address`() async throws {
        let wallet = Wallet()
        let phrase = try wallet.recoveryPhrase()
        #expect(phrase.words.count == 12)
        let restored = try RecoveryPhrase(phrase.words.joined(separator: " "))

        let originalAddress = try await wallet.address(for: phrase)
        let restoredAddress = try await wallet.address(for: restored, passphrase: "", path: DerivationPath("m/44'/501'/0'/0'"))

        #expect(originalAddress == restoredAddress)
    }

    /// Verifies cancellation before derivation without scheduling assumptions or sleeps.
    @Test
    func `Cancelled address derivation throws CancellationError`() async throws {
        let wallet = Wallet()
        let phrase = try RecoveryPhrase(Array(repeating: "abandon", count: 11).joined(separator: " ") + " about")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let task = Task { @concurrent in
            for await _ in gate {}
            return try await wallet.address(for: phrase)
        }
        task.cancel()
        continuation.finish()

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
