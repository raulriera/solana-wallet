import CryptoKit
import Foundation
import Testing
import Wallet

struct OneTimeAccountTests {
    private static let codeRoot = "85ab5e0262c48a29205f6beb1e222665aff6bab7a7d0505fe06745b613860a8c"

    struct Vector: Sendable, CustomTestStringConvertible {
        let index: UInt32
        let secret: String
        let publicKey: String
        let address: String
        let nullifierSecret: String
        let viewingPublicKey: String
        let codeRoot: String

        var testDescription: String { "Index \(index)" }
    }

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

    @Test(arguments: vectors)
    func `Code roots derive the reference one-time secrets`(_ vector: Vector) throws {
        let account = try OneTimeAccount(codeRoot: SymmetricKey(data: fixtureBytes(Self.codeRoot)), index: vector.index)

        #expect(account.secret.withUnsafeBytes { Array($0) } == (try fixtureBytes(vector.secret)))
        #expect(account.address == vector.address)
    }

    @Test(arguments: vectors)
    func `Secrets recover the reference address and private-balance keys`(_ vector: Vector) throws {
        let account = try OneTimeAccount(secret: SymmetricKey(data: fixtureBytes(vector.secret)))
        let keys = account.privateBalanceKeys

        #expect(account.address == vector.address)
        #expect(keys.nullifierSecret.withUnsafeBytes { Array($0) } == (try fixtureBytes(vector.nullifierSecret)))
        #expect(Array(keys.viewingKey.publicKey.compressedRepresentation) == (try fixtureBytes(vector.viewingPublicKey)))
        #expect(keys.codeRoot.withUnsafeBytes { Array($0) } == (try fixtureBytes(vector.codeRoot)))
    }

    @Test(arguments: vectors)
    func `Code roots derive the reference one-time addresses alone`(_ vector: Vector) throws {
        let codeRoot = SymmetricKey(data: try fixtureBytes(Self.codeRoot))

        #expect(try OneTimeAccount.address(codeRoot: codeRoot, index: vector.index) == vector.address)
    }

    @Test
    func `A batch of 500 one-time addresses derives distinct addresses`() throws {
        let codeRoot = SymmetricKey(data: try fixtureBytes(Self.codeRoot))

        let addresses = try (0..<500).map { try OneTimeAccount.address(codeRoot: codeRoot, index: UInt32($0)) }

        #expect(Set(addresses).count == 500)
        #expect(addresses.last == (try OneTimeAccount(codeRoot: codeRoot, index: 499)).address)
    }

    @Test(arguments: [0, 31, 33, 64])
    func `Code roots that aren't 32 bytes are rejected`(byteCount: Int) {
        let codeRoot = SymmetricKey(data: [UInt8](repeating: 7, count: byteCount))

        #expect(throws: OneTimeAccountError.invalidCodeRoot) { try OneTimeAccount(codeRoot: codeRoot, index: 0) }
        #expect(throws: OneTimeAccountError.invalidCodeRoot) { try OneTimeAccount.address(codeRoot: codeRoot, index: 0) }
    }

    @Test(arguments: [2_147_483_648, UInt32.max])
    func `Indices of 2³¹ or more are rejected`(index: UInt32) throws {
        let codeRoot = SymmetricKey(data: try fixtureBytes(Self.codeRoot))

        #expect(throws: OneTimeAccountError.invalidIndex) { try OneTimeAccount(codeRoot: codeRoot, index: index) }
        #expect(throws: OneTimeAccountError.invalidIndex) { try OneTimeAccount.address(codeRoot: codeRoot, index: index) }
    }

    @Test(arguments: [0, 31, 33, 64])
    func `Secrets that aren't 32 bytes are rejected`(byteCount: Int) {
        let secret = SymmetricKey(data: [UInt8](repeating: 7, count: byteCount))

        #expect(throws: OneTimeAccountError.invalidSecret) { try OneTimeAccount(secret: secret) }
    }

    @Test(arguments: vectors)
    func `Signatures verify with the account's public key`(_ vector: Vector) throws {
        let account = try OneTimeAccount(secret: SymmetricKey(data: fixtureBytes(vector.secret)))
        let message = Data("public signing fixture".utf8)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: fixtureBytes(vector.publicKey))

        let signature = try account.signature(for: message)

        #expect(signature.count == 64)
        #expect(key.isValidSignature(signature, for: message))
    }

    @Test(arguments: try PrivateBalanceVectors.load().derivationInputGuard.filter(\.isDerivationInput))
    func `Signing refuses Solana Rings derivation inputs`(_ vector: PrivateBalanceVectors.GuardVector) throws {
        let account = try OneTimeAccount(secret: SymmetricKey(data: fixtureBytes(Self.vectors[0].secret)))
        let message = Data(try fixtureBytes(vector.message))

        #expect(throws: SigningError.reservedMessage) { try account.signature(for: message) }
    }

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
