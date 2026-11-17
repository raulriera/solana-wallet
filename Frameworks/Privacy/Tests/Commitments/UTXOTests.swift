import ModularArithmetic
import Testing
@testable import Privacy

struct UTXOTests {
    private let owner: Poseidon.Element

    private let blinding: Poseidon.Element

    init() throws {
        let vectors = try CommitmentVectors.load()
        owner = try vectors.ed25519Rail.ownerHash()
        blinding = try Poseidon.Element(hex: vectors.blindingSeed.derivedOutputBlinding)
    }

    @Test(arguments: try UTXOTests.publishedUTXOs())
    func `Spent UTXO hashes and output commitments match the published transfers`(
        amount: UInt64,
        blinding: Poseidon.Element,
        treeID: UInt16,
        hex: String
    ) throws {
        let utxo = UTXO(owner: owner, asset: .nativeSOL, amount: amount, blinding: blinding, treeID: treeID)

        #expect(utxo.hash.bigEndianBytes == (try fixtureBytes(hex)))
    }

    @Test(arguments: try UTXOTests.emptyUTXOs())
    func `Empty-UTXO hashes match the published and independently derived values`(
        treeID: UInt16,
        blinding: Poseidon.Element,
        hex: String
    ) throws {
        #expect(UTXO.dummyHash(treeID: treeID, blinding: blinding).bigEndianBytes == (try fixtureBytes(hex)))
    }

    @Test(arguments: [
        (
            .nativeSOL, 0, 0,
            "254c1355cf5d096711abd71c874f815f5bf9a46fc70cc31d5e780458fefd2ec8"
        ),
        (
            .nativeSOL, .max, 0,
            "15d29a2046b1efa94321c8324f9e1449be37c7d6338198176970f709f3c1b3f8"
        ),
        (
            .nativeSOL, 1, 258,
            "2955117cb93fa5f46fb1b03f108904911f6dd874b98e75638407694251d40629"
        ),
        (
            .token(.usdc), .max, .max,
            "0d72ecb2cc24de96aeb1d604ddaac69d87e473fcf2dccd0f1e24a26643f2a911"
        ),
    ] as [(PrivateAsset, UInt64, UInt16, String)])
    func `Hashes match independently derived values`(
        asset: PrivateAsset, amount: UInt64, treeID: UInt16, hex: String
    ) throws {
        let utxo = UTXO(owner: owner, asset: asset, amount: amount, blinding: blinding, treeID: treeID)

        #expect(utxo.hash.bigEndianBytes == (try fixtureBytes(hex)))
    }

    private static func publishedUTXOs() throws -> [(UInt64, Poseidon.Element, UInt16, String)] {
        let spent = TransferVectors.spentInputs.map {
            ($0.amount, TransferVectors.blinding($0.blindingByte), $0.treeID, $0.hash)
        }
        return try spent + TransferVectors.outputs.map { ($0.amount, try $0.blinding(), $0.treeID, $0.commitment) }
    }

    private static func emptyUTXOs() throws -> [(UInt16, Poseidon.Element, String)] {
        let vector = try CommitmentVectors.load().dummyUTXOHash
        return [(vector.treeID, Poseidon.Element(vector.blinding), vector.hash)]
            + TransferVectors.paddingInputs.map { ($0.treeID, TransferVectors.blinding($0.blindingByte), $0.hash) }
            + [(.max, -.one, "00eee5890d80f5abd0d2e680a10c7bf7b94abf25d5b94b110e6132cec38e7848")]
    }
}
