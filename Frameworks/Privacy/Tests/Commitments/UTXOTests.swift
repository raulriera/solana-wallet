import ModularArithmetic
import Testing
@testable import Privacy

struct UTXOTests {
    private let nullifierKey: NullifierKey

    private let owner: Poseidon.Element

    private let blinding: Poseidon.Element

    init() throws {
        let vectors = try CommitmentVectors.load()
        nullifierKey = try vectors.ed25519Rail.nullifierKey()
        owner = try vectors.ed25519Rail.ownerHash()
        blinding = try Poseidon.Element(hex: vectors.blindingSeed.derivedOutputBlinding)
    }

    @Test(arguments: TransferVectors.spentInputs)
    func `Spent UTXO hashes match the published transfers`(_ input: TransferVectors.Input) throws {
        let utxo = UTXO(
            owner: owner, asset: .nativeSOL, amount: input.amount,
            blinding: TransferVectors.blinding(input.blindingByte), treeID: input.treeID
        )

        #expect(utxo.hash.bigEndianBytes == (try fixtureBytes(input.hash)))
    }

    @Test(arguments: TransferVectors.outputs)
    func `Output commitments match the published transfers`(_ output: TransferVectors.Output) throws {
        let utxo = UTXO(
            owner: owner, asset: .nativeSOL, amount: output.amount, blinding: try output.blinding(),
            treeID: output.treeID
        )

        #expect(utxo.hash.bigEndianBytes == (try fixtureBytes(output.commitment)))
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
            .nativeSOL, 1, .max,
            "11641733195ca24d891dfaa6f7e98f53d2ac0ff62e518ed9375cc4c1954565fa"
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
            .token(.usdc), 0, .max,
            "0a658aed74d0449f876305eb7fa90c859be24013cc1ee21c75658de3f50e8678"
        ),
        (
            .token(.usdc), 1, 0,
            "11bfdfed1491f99177a4aedf919fa43f140ec1ad30071744bd6601f4d2c9d32c"
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

    @Test
    func `Nullifiers match an independently derived value`() throws {
        let utxo = UTXO(owner: owner, asset: .nativeSOL, amount: 1, blinding: blinding, treeID: 0)

        #expect(utxo.nullifier(using: nullifierKey).bigEndianBytes == (try fixtureBytes("0cd4871b07798e5135b2556f8c8ca0becca860a35ca286ab5b3a2215d920ee8f")))
    }

    private static func emptyUTXOs() throws -> [(UInt16, Poseidon.Element, String)] {
        let vector = try CommitmentVectors.load().dummyUTXOHash
        return [(vector.treeID, Poseidon.Element(vector.blinding), vector.hash)]
            + TransferVectors.paddingInputs.map { ($0.treeID, TransferVectors.blinding($0.blindingByte), $0.hash) }
            + [(.max, -.one, "00eee5890d80f5abd0d2e680a10c7bf7b94abf25d5b94b110e6132cec38e7848")]
    }
}
