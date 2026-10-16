import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the public input hash of transact proofs against zolana's published vectors.
///
/// The assembly tests use the byte literals of `sdk-libs/client/tests/assembly_vectors.rs` at tag
/// v0.4.0-alpha (Apache-2.0), copied unchanged as hexadecimal: a two-input, four-output transfer in
/// tree 3 from the Ed25519 key with secret 32 bytes of 0x11 to the one with 32 bytes of 0x22, whose
/// tree slot has the roots `00 ‖ 0x54 × 31` and `00 ‖ 0x59 × 31`. `PublicInputVectors-LICENSE.txt`
/// records the source and its digest.
struct PublicInputsTests {
    /// Verifies the published transfer hashes that carry output owner identities, with full and
    /// compact padding and up to 36 inputs.
    ///
    /// - Parameter vector: A published transfer.
    @Test(arguments: try PublicInputVectors.load().transfers.filter { $0.outputOwnerIdentities != nil })
    func `Hashes match the published transfers`(_ vector: PublicInputVectors.Transfer) throws {
        let publicInputs = try vector.publicInputs()

        let hash = publicInputs.hash(treeSlots: try vector.treeSlots.map { try $0.slot() })

        #expect(publicInputs.elements.count == 17)
        #expect(hash.bigEndianBytes == (try fixtureBytes(vector.publicInputHash)))
    }

    /// Verifies that the published transfer left out is the one without output owner identities,
    /// which the default ring always publishes.
    @Test
    func `One published transfer has no owner identities`() throws {
        let names = try PublicInputVectors.load().transfers.filter { $0.outputOwnerIdentities == nil }.map(\.name)

        #expect(names == ["compact_5x4_without_owner_chain"])
    }

    /// Verifies zolana's proof request fixture: the prover inserts two trees' slots at index 2 of
    /// 15 public inputs.
    @Test
    func `Hashes match the published proof request`() throws {
        let vector = try PublicInputVectors.load().indexedProof

        let hash = PublicInputs.hash(
            elements: try vector.publicInputs.map(PublicInputVectors.IndexedProof.element),
            treeSlots: try vector.trees.map { try $0.slot() }
        )

        #expect(hash == (try PublicInputVectors.IndexedProof.element(vector.publicInputHash)))
    }

    /// Verifies a tree slot's hash and the chain of that slot followed by 4 unused slots.
    @Test
    func `Tree slots match the published chain`() throws {
        let vector = try HashChainVectors.load().treeSlots
        let slot = PublicInputs.TreeSlot(
            treeID: vector.treeID, utxoRoot: Poseidon.Element(vector.utxoRoot), nullifierRoot: Poseidon.Element(vector.nullifierRoot)
        )

        #expect(slot.hash.bigEndianBytes == (try fixtureBytes(vector.slotHash)))
        #expect(PublicInputs.treeSlotsChain([slot]).bigEndianBytes == (try fixtureBytes(vector.singleTreeChain)))
    }

    /// Verifies zolana's assembled transfer, and its variant whose last output is an ownerless
    /// padding slot tagged with 32 bytes of 0x6d: one signer, the payer, of 3; the input flags of
    /// two inputs in tree position 0; and the zero chain of one group for the cache.
    ///
    /// - Parameters:
    ///   - lastOutputHash: The UTXO hash of output slot 3.
    ///   - lastOutputTag: The view tag of output slot 3, or `nil` for the sender's.
    ///   - privateTransactionHash: The private transaction hash.
    ///   - expected: The public input hash.
    @Test(arguments: [
        (
            "031525ba7484687e92e323f2698262bee7a32d1aecf9d0d922b9d295655308d5", nil,
            "1fa917db61171291cbaf35e9ee771bb3be2183d99654c460ac21f938e8d425cd",
            "2e7835052e633a4ed910506c21428f5b248b24d772206f7253eb1d4beb2977e8"
        ),
        (
            "1e6761745ba733b82a4881e44b0ab245fb23cd0817074d4bbb60118111e1525f", [UInt8](repeating: 0x6d, count: 32),
            "13e0fe895161b4755c993d7131f0112445ef09916691869f97a1c116d6f12ca5",
            "19e1ddd9b51ad4ccbac173523a088ebedab9f0735df2b1b885cbc0288143e5e6"
        ),
    ] as [(String, [UInt8]?, String, String)])
    func `Hashes match zolana's assembled transfer`(
        lastOutputHash: String,
        lastOutputTag: [UInt8]?,
        privateTransactionHash: String,
        expected: String
    ) throws {
        let sender = Array(try Curve25519.Signing.PrivateKey(rawRepresentation: [UInt8](repeating: 0x11, count: 32)).publicKey.rawRepresentation)
        let recipient = Array(try Curve25519.Signing.PrivateKey(rawRepresentation: [UInt8](repeating: 0x22, count: 32)).publicKey.rawRepresentation)
        let outputHashes = try [
            "040488dddd0470c95fe3ce77027a745dbbc375a1bac92b4cb73ebc00c3e7eb64",
            "1967fbc6c92b8d719ec2231f0da989cc2d87b3c411b78463824e70c99e5373d0",
            "2478af083742ca4e0ee97bf3148d61a09708786c16cae9bc25ee7aa645298312",
            lastOutputHash,
        ].map { try Poseidon.Element(hex: $0) }
        let publicInputs = PublicInputs(
            nullifiers: try [
                "063a630585ecb050144d76efb6e5eaafddc523017bd7bf8427528a7ed8218f6b",
                "2661310161ab2bc5d2376d26c09061ce05313080b036153b4daf88a601b7f561",
            ].map { try Poseidon.Element(hex: $0) },
            outputHashes: outputHashes, outputTreeID: 3,
            privateTransactionHash: try Poseidon.Element(hex: privateTransactionHash),
            externalDataHash: try Poseidon.Element(hex: "0090dc7187243edfa71b3ab71ba8e126360048410d4cfec1d1b7eb83e2c00cd2"),
            publicAssets: Array(repeating: .zero, count: 3), publicAmounts: Array(repeating: .zero, count: 3), ringProgramID: .zero,
            signerIdentities: [OwnerIdentity.solana(signingPublicKey: sender), .zero, .zero],
            inputFlags: InputFlags.pack(treeIndexes: [0, 0]),
            outputOwnerIdentities: [recipient, sender, sender, lastOutputTag ?? sender].map { OwnerIdentity.solana(signingPublicKey: $0) },
            cacheTreeID: .zero, cacheReadHashChain: HashChain.zeroSuffix(groups: 1)
        )
        let slot = PublicInputs.TreeSlot(treeID: 3, utxoRoot: TransferVectors.blinding(0x54), nullifierRoot: TransferVectors.blinding(0x59))

        #expect(publicInputs.hash(treeSlots: [slot]).bigEndianBytes == (try fixtureBytes(expected)))
    }
}
