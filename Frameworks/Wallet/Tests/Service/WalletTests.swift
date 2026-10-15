import Testing
import Wallet

/// Tests the wallet through its public API without privileged access or networking.
struct WalletTests {
    /// Verifies recovery across paths and significant or Unicode-normalized passphrases.
    ///
    /// The last three passphrases need NFKD to reorder combining marks after decomposition.
    /// Expected addresses were derived independently with Python hashlib/HMAC and OpenSSL Ed25519;
    /// the reordering rows use Python's NFKD and RFC 8032 Ed25519, checked against CryptoKit.
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
        ("m/44'/501'/0'/0'", "e\u{301}\u{FF9E}", "CsudTpooGzAXxo7ndUc6K8EvQmQT7vNs4zXTADUspNpF"),
        ("m/44'/501'/0'/0'", "\u{1FFD}\u{316}", "A8itvwcr8twSY46T95djD6AwQzhYZufYb2Jd4BNWRZad"),
        ("m/44'/501'/0'/0'", "e\u{301}\u{F73}", "6n5ypUditR13kFk4cxvwe2z5qpsXK4wG5AfPUsEJMddv"),
    ])
    func `Imported recovery phrases derive expected Solana addresses`(path: String, passphrase: String, expected: String) async throws {
        let wallet: any WalletProviding = Wallet()
        let phrase = try RecoveryPhrase("  " + Array(repeating: "ABANDON", count: 11).joined(separator: " \n\t") + " ABOUT  ")

        let accounts = try await wallet.accounts(for: phrase, passphrase: passphrase, paths: [DerivationPath(path)])

        #expect(accounts.map(\.address) == [expected])
    }

    /// Verifies that a newly generated twelve-word wallet restores the same default account.
    @Test
    func `New twelve-word wallets restore their address`() async throws {
        let wallet = Wallet()
        let phrase = try wallet.recoveryPhrase(wordCount: .twelve)
        #expect(phrase.words.count == 12)
        let restored = try RecoveryPhrase(phrase.words.joined(separator: " "))
        let path = try DerivationPath("m/44'/501'/0'/0'")

        async let original = wallet.accounts(for: phrase, passphrase: "", paths: [.solana])
        async let restoredAccounts = wallet.accounts(for: restored, passphrase: "", paths: [path])
        let (originalAddresses, restoredAddresses) = try await (original.map(\.address), restoredAccounts.map(\.address))

        #expect(originalAddresses == restoredAddresses)
    }
}
