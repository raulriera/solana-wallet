import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing

struct TransactionViewingKeyTests {
    @Test
    func `Transaction viewing keys match the published vector`() throws {
        let vector = try EncryptionVectors.load().transactionViewing
        let viewingKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(vector.viewingSecret))

        let key = try TransactionViewingKey.derive(viewingKey: viewingKey, firstNullifier: Poseidon.Element(hex: vector.firstNullifier))

        #expect(Array(key.rawRepresentation) == (try fixtureBytes(vector.transactionViewingScalar)))
        #expect(Array(key.publicKey.compressedRepresentation) == (try fixtureBytes(vector.transactionViewingPublicKey)))
    }

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
