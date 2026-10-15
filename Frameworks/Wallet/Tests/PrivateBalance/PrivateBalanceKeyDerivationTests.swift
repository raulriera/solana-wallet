import CryptoKit
import Testing
import Wallet

/// Verifies private-balance key derivation through the public protocol against zolana's golden keys.
struct PrivateBalanceKeyDerivationTests {
    /// Verifies the nullifier secret, viewing scalar, and viewing public key of each golden account.
    ///
    /// - Parameter vector: A golden account and its published keys.
    @Test(arguments: try PrivateBalanceVectors.load().accounts)
    func `Golden accounts derive the published private-balance keys`(_ vector: PrivateBalanceVectors.Account) async throws {
        let deriver: any PrivateBalanceKeyDeriving = Wallet()

        let keys = try await deriver.privateBalanceKeys(
            using: PublicRecovery.phrase(),
            expectedAddress: PublicRecovery.addresses[Int(vector.account)],
            passphrase: "", path: DerivationPath("m/44'/501'/\(vector.account)'/0'")
        )

        #expect(keys.nullifierSecret.withUnsafeBytes { Array($0) } == (try fixtureBytes(vector.nullifierSecret)))
        #expect(Array(keys.viewingKey.rawRepresentation) == (try fixtureBytes(vector.viewingSecret)))
        #expect(Array(keys.viewingKey.publicKey.compressedRepresentation) == (try fixtureBytes(vector.viewingPubkey)))
    }

    /// Verifies that keys are derived only for the account at the expected address.
    ///
    /// The cases are a different passphrase, another account's address, a Kelvin sign in place of
    /// `K`, a character outside the Base58 alphabet, and Base58 text that isn't 32 bytes long.
    ///
    /// - Parameters:
    ///   - address: The expected address for account 0.
    ///   - passphrase: The BIP-39 passphrase.
    @Test(arguments: [
        (PublicRecovery.addresses[0], "different account"),
        (PublicRecovery.addresses[1], ""),
        ("HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3D\u{212A}pqk", ""),
        ("HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpq0", ""),
        ("HAgk14JpMQLgt6rVgv7cBQFJ", ""),
    ])
    func `Private-balance keys require the account at the expected address`(address: String, passphrase: String) async throws {
        let recovery = try PublicRecovery.phrase()

        await #expect(throws: PrivateBalanceError.accountMismatch) {
            try await Wallet().privateBalanceKeys(
                using: recovery, expectedAddress: address, passphrase: passphrase, path: .solana
            )
        }
    }

    /// Verifies that Solana's other discovered path family has no private-balance keys, even with
    /// its own correct address.
    @Test
    func `Private-balance keys refuse paths outside the Solana account family`() async throws {
        let recovery = try PublicRecovery.phrase()
        let path = try DerivationPath("m/44'/501'/0'")

        await #expect(throws: PrivateBalanceError.unsupportedPath) {
            try await Wallet().privateBalanceKeys(
                using: recovery, expectedAddress: "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL",
                passphrase: "", path: path
            )
        }
    }

    /// Verifies cancellation prevents key delivery without relying on task scheduling.
    @Test
    func `Cancelled private-balance derivation throws CancellationError`() async throws {
        let recovery = try PublicRecovery.phrase()
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let task = Task { @concurrent in
            for await _ in gate {}
            return try await Wallet().privateBalanceKeys(
                using: recovery, expectedAddress: PublicRecovery.addresses[0],
                passphrase: "", path: .solana
            )
        }
        task.cancel()
        continuation.finish()

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
