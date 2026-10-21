import CryptoKit
import Foundation
import Testing
import Wallet

/// Verifies one-time account derivation, validation, signing, and diagnostics through the public API.
///
/// The expected keys were derived independently with Python's `hashlib` and `hmac`, and pure-Python
/// Ed25519 and P-256 arithmetic, by a SLIP-0010 reference that first reproduces zolana's golden keys.
/// The code root is account 0's of `PublicRecovery`.
struct OneTimeAccountTests {
    /// The code root of `PublicRecovery`'s account 0.
    private static let codeRoot = "85ab5e0262c48a29205f6beb1e222665aff6bab7a7d0505fe06745b613860a8c"

    /// The reference keys of one index of ``codeRoot``.
    struct Vector: Sendable, CustomTestStringConvertible {
        /// The one-time account's index.
        let index: UInt32
        /// The 32-byte secret at `m/index'`.
        let secret: String
        /// The 32-byte Ed25519 public key at `m/44'/501'/0'/0'` of the secret.
        let publicKey: String
        /// The public key in Base58.
        let address: String
        /// The 31-byte nullifier secret of the secret's account 0.
        let nullifierSecret: String
        /// The 33-byte compressed P-256 viewing public key of the secret's account 0.
        let viewingPublicKey: String
        /// The 32-byte code root of the secret's account 0.
        let codeRoot: String

        /// The index, in test results.
        var testDescription: String { "Index \(index)" }
    }

    /// The first two indices and the largest one.
    static let vectors = [
        Vector(
            index: 0,
            secret: "cce25a63080e57f4917c053b71115ac420fb9cbb60b166d60de7ee3899b8654a",
            publicKey: "83c9d93274ebcf4d946c92de4109681d7f077e2c0dce7850cc64b4995b72cbb0",
            address: "9sSvbwENS9A8HmYD9Jfe6vSemnWdsiy2KSRpxYscFXom",
            nullifierSecret: "37f6efceca52679ab628d59aea6730d18037ffa41c2b79582062041ab1eb59",
            viewingPublicKey: "03011d6f5dd2b2f490c0f27f9a8781583f6e2dc70e6a540625f507c9f10cbea453",
            codeRoot: "c0b84e396a8827aa1bc9b601525c49b06ae889db2868e1f83b383c4a7c5b8cd5"
        ),
        Vector(
            index: 1,
            secret: "dbaed21af7af9f863fd21b8e76e60bad276ac09b201b93b2b84eb5cf4356418c",
            publicKey: "27560def591723ac551a0d23d3e112b6052d6453b6ef83c73a7cf587b0388145",
            address: "3eZ1RBpo1ZMXNMokUZZjP5haaWkx2HqTF4dhatDZB9ba",
            nullifierSecret: "dbc9767939315b30430a0dbeed64b64982acb7122b4f0d46c8c264119e35fd",
            viewingPublicKey: "0245ff6235ea9224e1fd9ea404d0dd77d6266c986e3686990d48e4f2258ebaea6c",
            codeRoot: "daa3901dd7ab7e54e3be35f25b5f3b693329b377e687c1ed3f20564ec56167f7"
        ),
        Vector(
            index: 2_147_483_647,
            secret: "69cbe3a6961bcee5c93eaa38c3c8ba81f1c609d5cbfb9c8afb28eaa786fccbc1",
            publicKey: "4c8152bdd8f197ebbf49f04ea84a07c8746d2bd541a0e8ec8827954ad62650ae",
            address: "69eMq7vQwvW538JRTJc8R1eGv1NXbj77JSvatv3rQhwj",
            nullifierSecret: "38ad7206c1178874134b00f3a5853dd75b4e2e0d6dd97a2a5ea89d2f21d04d",
            viewingPublicKey: "02c454fcc72991143711ec007f7ea16387e1c8b687a9a230e14f8bb339de9df475",
            codeRoot: "0994dcc75af74d259e4d9af01437c2334fbfd0afc6e9a1bda235cc232db9043b"
        ),
    ]

    /// Verifies the secret that each index of a code root derives.
    ///
    /// - Parameter vector: An index and its reference keys.
    @Test(arguments: vectors)
    func `Code roots derive the reference one-time secrets`(_ vector: Vector) throws {
        let account = try OneTimeAccount(codeRoot: SymmetricKey(data: fixtureBytes(Self.codeRoot)), index: vector.index)

        #expect(account.secret.withUnsafeBytes { Array($0) } == (try fixtureBytes(vector.secret)))
        #expect(account.address == vector.address)
    }

    /// Verifies the address and private-balance keys that each secret recovers.
    ///
    /// - Parameter vector: A secret and its reference keys.
    @Test(arguments: vectors)
    func `Secrets recover the reference address and private-balance keys`(_ vector: Vector) throws {
        let account = try OneTimeAccount(secret: SymmetricKey(data: fixtureBytes(vector.secret)))
        let keys = account.privateBalanceKeys

        #expect(account.address == vector.address)
        #expect(keys.nullifierSecret.withUnsafeBytes { Array($0) } == (try fixtureBytes(vector.nullifierSecret)))
        #expect(Array(keys.viewingKey.publicKey.compressedRepresentation) == (try fixtureBytes(vector.viewingPublicKey)))
        #expect(keys.codeRoot.withUnsafeBytes { Array($0) } == (try fixtureBytes(vector.codeRoot)))
    }

    /// Verifies that the address-only derivation of a code root's index matches the reference address.
    ///
    /// - Parameter vector: An index and its reference address.
    @Test(arguments: vectors)
    func `Code roots derive the reference one-time addresses alone`(_ vector: Vector) throws {
        let codeRoot = SymmetricKey(data: try fixtureBytes(Self.codeRoot))

        #expect(try OneTimeAccount.address(codeRoot: codeRoot, index: vector.index) == vector.address)
    }

    /// Verifies that a batch of 500 addresses, the size of a redeem-code discovery read, derives distinct
    /// addresses that match the full derivation; this test's duration measures the batch.
    @Test
    func `A batch of 500 one-time addresses derives distinct addresses`() throws {
        let codeRoot = SymmetricKey(data: try fixtureBytes(Self.codeRoot))

        let addresses = try (0..<500).map { try OneTimeAccount.address(codeRoot: codeRoot, index: UInt32($0)) }

        #expect(Set(addresses).count == 500)
        #expect(addresses.last == (try OneTimeAccount(codeRoot: codeRoot, index: 499)).address)
    }

    /// Verifies that only a 32-byte code root derives accounts or addresses.
    ///
    /// - Parameter byteCount: A code root length other than 32.
    @Test(arguments: [0, 31, 33, 64])
    func `Code roots that aren't 32 bytes are rejected`(byteCount: Int) {
        let codeRoot = SymmetricKey(data: [UInt8](repeating: 7, count: byteCount))

        #expect(throws: OneTimeAccountError.invalidCodeRoot) { try OneTimeAccount(codeRoot: codeRoot, index: 0) }
        #expect(throws: OneTimeAccountError.invalidCodeRoot) { try OneTimeAccount.address(codeRoot: codeRoot, index: 0) }
    }

    /// Verifies that indices outside the hardened derivation range derive no account or address.
    ///
    /// - Parameter index: An index of 2³¹ or more.
    @Test(arguments: [2_147_483_648, UInt32.max])
    func `Indices of 2³¹ or more are rejected`(index: UInt32) throws {
        let codeRoot = SymmetricKey(data: try fixtureBytes(Self.codeRoot))

        #expect(throws: OneTimeAccountError.invalidIndex) { try OneTimeAccount(codeRoot: codeRoot, index: index) }
        #expect(throws: OneTimeAccountError.invalidIndex) { try OneTimeAccount.address(codeRoot: codeRoot, index: index) }
    }

    /// Verifies that only a 32-byte secret recovers an account.
    ///
    /// - Parameter byteCount: A secret length other than 32.
    @Test(arguments: [0, 31, 33, 64])
    func `Secrets that aren't 32 bytes are rejected`(byteCount: Int) {
        let secret = SymmetricKey(data: [UInt8](repeating: 7, count: byteCount))

        #expect(throws: OneTimeAccountError.invalidSecret) { try OneTimeAccount(secret: secret) }
    }

    /// Verifies that a signature verifies with the reference public key.
    ///
    /// - Parameter vector: A secret and its reference public key.
    @Test(arguments: vectors)
    func `Signatures verify with the account's public key`(_ vector: Vector) throws {
        let account = try OneTimeAccount(secret: SymmetricKey(data: fixtureBytes(vector.secret)))
        let message = Data("public signing fixture".utf8)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: fixtureBytes(vector.publicKey))

        let signature = try account.signature(for: message)

        #expect(signature.count == 64)
        #expect(key.isValidSignature(signature, for: message))
    }

    /// Verifies that signing refuses Solana Rings derivation inputs.
    ///
    /// - Parameter vector: A zolana message that's a derivation input.
    @Test(arguments: try PrivateBalanceVectors.load().derivationInputGuard.filter(\.isDerivationInput))
    func `Signing refuses Solana Rings derivation inputs`(_ vector: PrivateBalanceVectors.GuardVector) throws {
        let account = try OneTimeAccount(secret: SymmetricKey(data: fixtureBytes(Self.vectors[0].secret)))
        let message = Data(try fixtureBytes(vector.message))

        #expect(throws: SigningError.reservedMessage) { try account.signature(for: message) }
    }

    /// Verifies that printing, dumping, and reflecting the account omit its secrets and address.
    @Test
    func `One-time account diagnostics omit the secrets`() throws {
        let account = try OneTimeAccount(secret: SymmetricKey(data: fixtureBytes(Self.vectors[0].secret)))
        var output = ""
        dump(account, to: &output)

        #expect(account.description == "OneTimeAccount")
        #expect(account.debugDescription == "OneTimeAccount")
        #expect(String(reflecting: account) == "OneTimeAccount")
        #expect(output == "- OneTimeAccount\n")
        #expect(Mirror(reflecting: account).children.isEmpty)
    }
}
