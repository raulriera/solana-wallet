import CryptoKit
import Foundation
import Testing
import Wallet

struct SigningTests {
    @Test(arguments: [
        ("", "m/44'/501'/0'/0'", "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk",
         "8DYnYkanW53jNJ7UKxXiMvZRj8IPX81PHWToH5vSWPc="),
        ("TREZOR", "m/44'/501'/1'/0'", "8CW93AFYFKj2rKZRq3YjLesb4XbgtAiq8k2FgfruVZL5",
         "avQk/DwMx04ex+GYBKContNRuDzLEt0PObiUpqRJYxI=")
    ])
    func `Recovered accounts sign the exact supplied bytes`(passphrase: String, path: String, address: String, publicKey: String) async throws {
        let signer: any MessageSigning = Wallet()
        let message = Data("public signing fixture".utf8)
        let signature = try await signer.signature(
            for: message, using: PublicRecovery.phrase(), expectedAddress: address,
            passphrase: passphrase, path: DerivationPath(path)
        )
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: #require(Data(base64Encoded: publicKey)))

        #expect(signature.count == 64)
        #expect(key.isValidSignature(signature, for: message))
    }

    @Test
    func `Signing rejects recovery material for another sender`() async throws {
        let recovery = try PublicRecovery.phrase()

        await #expect(throws: SigningError.signerMismatch) {
            try await Wallet().signature(
                for: Data("public signing fixture".utf8), using: recovery,
                expectedAddress: PublicRecovery.addresses[0],
                passphrase: "different account", path: .solana
            )
        }
    }

    @Test
    func `Signing rejects a Unicode lookalike in the sender address`() async throws {
        let recovery = try PublicRecovery.phrase()
        let address = "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3D\u{212A}pqk"

        await #expect(throws: SigningError.signerMismatch) {
            try await Wallet().signature(for: Data("public signing fixture".utf8),
                                         using: recovery, expectedAddress: address, passphrase: "", path: .solana)
        }
    }

    @Test(arguments: try PrivateBalanceVectors.load().derivationInputGuard.filter(\.isDerivationInput))
    func `Signing refuses Solana Rings derivation inputs`(_ vector: PrivateBalanceVectors.GuardVector) async throws {
        let recovery = try PublicRecovery.phrase()
        let message = Data(try fixtureBytes(vector.message))

        await #expect(throws: SigningError.reservedMessage) {
            try await Wallet().signature(
                for: message, using: recovery, expectedAddress: PublicRecovery.addresses[0],
                passphrase: "", path: .solana
            )
        }
    }

    @Test(arguments: try PrivateBalanceVectors.load().derivationInputGuard.filter { !$0.isDerivationInput })
    func `Signing accepts messages that only resemble derivation inputs`(_ vector: PrivateBalanceVectors.GuardVector) async throws {
        let message = Data(try fixtureBytes(vector.message))

        let signature = try await Wallet().signature(
            for: message, using: PublicRecovery.phrase(),
            expectedAddress: PublicRecovery.addresses[0], passphrase: "", path: .solana
        )
        let account = try #require(PrivateBalanceVectors.load().accounts.first)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: fixtureBytes(account.signingPubkey))

        #expect(key.isValidSignature(signature, for: message))
    }

    @Test
    func `Cancelled signing throws CancellationError`() async throws {
        let recovery = try PublicRecovery.phrase()
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let task = Task { @concurrent in
            for await _ in gate {}
            return try await Wallet().signature(
                for: Data("public signing fixture".utf8), using: recovery,
                expectedAddress: PublicRecovery.addresses[0], passphrase: "", path: .solana
            )
        }
        task.cancel()
        continuation.finish()

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
