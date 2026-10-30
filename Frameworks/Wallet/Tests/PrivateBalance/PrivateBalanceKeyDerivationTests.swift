import CryptoKit
import Testing
import Wallet

struct PrivateBalanceKeyDerivationTests {
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

    @Test(arguments: [
        (0, "85ab5e0262c48a29205f6beb1e222665aff6bab7a7d0505fe06745b613860a8c"),
        (1, "589f28bfe6d251368c6dec380694e3fb871f76fbe07271729db0fc88be85344d"),
    ])
    func `Accounts derive their code root`(account: UInt32, codeRoot: String) async throws {
        let keys = try await Wallet().privateBalanceKeys(
            using: PublicRecovery.phrase(), expectedAddress: PublicRecovery.addresses[Int(account)],
            passphrase: "", path: DerivationPath("m/44'/501'/\(account)'/0'")
        )

        #expect(keys.codeRoot.withUnsafeBytes { Array($0) } == (try fixtureBytes(codeRoot)))
    }

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
