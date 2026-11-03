import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing

struct TransactionViewingKeyTests {
    @Test
    func `Transaction viewing keys match the published vector`() throws {
        let vector = try EncryptionVectors.load().transactionViewing
        let viewingKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(vector.viewingSecret))

        let key = try TransactionViewingKey.derive(viewingKey: viewingKey, firstNullifier: Poseidon.Element(hex: vector.firstNullifier))

        #expect(Array(key.rawRepresentation) == (try fixtureBytes(vector.transactionViewingSecret)))
        #expect([UInt8](key.publicKey.taggedRepresentation) == (try fixtureBytes(vector.transactionViewingPublicKey)))
    }

    @Test(arguments: try TransactionViewingKeyTests.independentKeys())
    func `Transaction viewing keys match independently derived values`(
        viewingSecret: String,
        firstNullifier: String,
        secret: String,
        publicKey: String
    ) throws {
        let viewingKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(viewingSecret))

        let key = try TransactionViewingKey.derive(viewingKey: viewingKey, firstNullifier: Poseidon.Element(hex: firstNullifier))

        #expect(Array(key.rawRepresentation) == (try fixtureBytes(secret)))
        #expect([UInt8](key.publicKey.taggedRepresentation) == (try fixtureBytes(publicKey)))
    }

    private static func independentKeys() throws -> [(String, String, String, String)] {
        let viewingSecret = try CommitmentVectors.load().ed25519Rail.viewingSecret
        let firstNullifier = try #require(TransferVectors.outputs.first).firstNullifier
        return [
            (
                viewingSecret, firstNullifier,
                "3846d5fb85f031ff42d4e191fb908982c81326b4b1aced4706b7e0b55708b34a",
                "046cd494021cc3acba3bcc49331d7afe0e161574e1a9d0c837ed568c0c006fff46"
            ),
            (
                "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000",
                "f0e5a533f720d08491def09f5fc8018dd8fc5328f2dfea2dd54ce5b410d58477",
                "04a73eb5ba2a7a547fdd663c290e91a1cb0a4cb8594fe82e3dd2ba7b95a9b7f37c"
            ),
        ]
    }
}
