import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the derivation of transaction viewing keys.
struct TransactionViewingKeyTests {
    /// Verifies the derivation against zolana's published vector.
    ///
    /// The vector's viewing secret is 3 and its first nullifier is 11.
    @Test
    func `Transaction viewing keys match the published vector`() throws {
        let vector = try EncryptionVectors.load().transactionViewing
        let viewingKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(vector.viewingSecret))

        let key = try TransactionViewingKey.derive(viewingKey: viewingKey, firstNullifier: Poseidon.Element(hex: vector.firstNullifier))

        #expect(Array(key.rawRepresentation) == (try fixtureBytes(vector.transactionViewingScalar)))
        #expect(Array(key.publicKey.compressedRepresentation) == (try fixtureBytes(vector.transactionViewingPublicKey)))
    }

    /// Verifies the derivation against independently derived keys.
    ///
    /// The expected values come from a separate Python implementation of P-256, HKDF, and RFC 9380's
    /// hash to curve. The first case is the Ed25519 rail's viewing key with the first nullifier of
    /// zolana's transfer case A, 32-byte values unlike the vector's small integers; the second is the
    /// largest viewing secret, n - 1, with the largest first nullifier, r - 1.
    ///
    /// - Parameters:
    ///   - viewingSecret: The account's 32-byte viewing secret.
    ///   - firstNullifier: The transaction's first nullifier.
    ///   - scalar: The expected scalar of the transaction viewing key.
    ///   - publicKey: The expected SEC1 compressed public key.
    @Test(arguments: try TransactionViewingKeyTests.independentKeys())
    func `Transaction viewing keys match independently derived values`(
        viewingSecret: String,
        firstNullifier: String,
        scalar: String,
        publicKey: String
    ) throws {
        let viewingKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(viewingSecret))

        let key = try TransactionViewingKey.derive(viewingKey: viewingKey, firstNullifier: Poseidon.Element(hex: firstNullifier))

        #expect(Array(key.rawRepresentation) == (try fixtureBytes(scalar)))
        #expect(Array(key.publicKey.compressedRepresentation) == (try fixtureBytes(publicKey)))
    }

    /// Gathers the independently derived cases: the Ed25519 rail's viewing secret with case A's
    /// first nullifier, and the largest viewing secret with the largest first nullifier.
    ///
    /// - Returns: Each case's viewing secret, first nullifier, scalar, and public key.
    /// - Throws: A test failure if a fixture is missing or malformed, or an error if it can't be read
    ///   or decoded.
    private static func independentKeys() throws -> [(String, String, String, String)] {
        let viewingSecret = try CommitmentVectors.load().ed25519Rail.viewingSecret
        let firstNullifier = try #require(TransferVectors.outputs.first).firstNullifier
        return [
            (
                viewingSecret, firstNullifier,
                "16b79cb62202513becf0508cdc6c31e7039eb2f670e125be4cc7123dace2272e",
                "031bcd477c8e4a44aa0fa3c96e073abd93e9cca0d626d50531298fd71b684cff62"
            ),
            (
                "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550",
                "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000",
                "095d79ec13d128666a45fa492eb0100d16c89924a1f4906ea55bd0c3443f5ba9",
                "02d27bd2c44a036a5eb552c0d1fea59d5ab1b2da35074f40d71dfb4a574b2cae03"
            ),
        ]
    }
}
