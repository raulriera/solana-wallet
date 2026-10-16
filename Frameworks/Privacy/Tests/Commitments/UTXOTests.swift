import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies UTXO hashes, empty-UTXO hashes, and UTXO nullifiers.
///
/// zolana publishes the empty-UTXO hash of its blinding-seed vectors and, in `hash_vectors.rs`, the
/// hashes of the owned SOL UTXOs and padding inputs of two transfers. The edge cases that zolana
/// doesn't publish, such as the USDC mint, the largest amount and tree ID, tree 258, and r - 1
/// blindings, come from a separate Python implementation of Poseidon and `hash_bytes_N`.
struct UTXOTests {
    /// The nullifier key of zolana's Ed25519 rail.
    private let nullifierKey: NullifierKey

    /// The owner hash of zolana's Ed25519 rail, from its published signing public key and
    /// nullifier secret.
    private let owner: Poseidon.Element

    /// The published output blinding of slot 3 in zolana's blinding-seed vector.
    private let blinding: Poseidon.Element

    /// Derives the Ed25519 rail's nullifier key and owner hash, and reads the published output
    /// blinding from the fixture.
    ///
    /// - Throws: A test failure if the fixture is missing or malformed, or an error if it can't be
    ///   read or decoded.
    init() throws {
        let vectors = try CommitmentVectors.load()
        let rail = vectors.ed25519Rail
        let signingPublicKey = try fixtureBytes(#require(rail.signerPubkey))
        nullifierKey = try NullifierKey(secret: SymmetricKey(data: fixtureBytes(rail.nullifierSecret)))
        owner = OwnerIdentity.ownerHash(signingPublicKey: signingPublicKey, nullifierPublicKey: nullifierKey.publicKey)
        blinding = try Poseidon.Element(hex: vectors.blindingSeed.derivedOutputBlinding)
    }

    /// Verifies the hashes of spent UTXOs against zolana's published transfers.
    ///
    /// Each UTXO holds SOL and is owned by the Ed25519 rail. Trees 3 and 1, unlike tree 0, read
    /// differently in the other byte order, so they check the tree ID's encoding.
    ///
    /// - Parameter input: A published spent UTXO and its hash.
    @Test(arguments: TransferVectors.spentInputs)
    func `Spent UTXO hashes match the published transfers`(_ input: TransferVectors.Input) throws {
        let utxo = UTXO(
            owner: owner, mint: Array(repeating: 0, count: 32), amount: input.amount,
            blinding: TransferVectors.blinding(input.blindingByte), treeID: input.treeID
        )

        #expect(utxo.hash.bigEndianBytes == (try fixtureBytes(input.hash)))
    }

    /// Verifies the commitments of the sender's outputs against zolana's published transfers.
    ///
    /// Each output's blinding derives from its proof's first nullifier and the published blinding
    /// seed, through the output blinding seed. The zero-amount padding outputs are UTXOs that the
    /// sender owns, not empty UTXOs.
    ///
    /// - Parameter output: A published output and its commitment.
    @Test(arguments: TransferVectors.outputs)
    func `Output commitments match the published transfers`(_ output: TransferVectors.Output) throws {
        let firstNullifier = try Poseidon.Element(hex: output.firstNullifier)
        let outputBlindingSeed = TransactBlinding.outputBlindingSeed(
            firstNullifier: firstNullifier, blindingSeed: TransferVectors.blindingSeed
        )
        let utxo = UTXO(
            owner: owner, mint: Array(repeating: 0, count: 32), amount: output.amount,
            blinding: TransactBlinding.outputBlinding(
                firstNullifier: firstNullifier, outputBlindingSeed: outputBlindingSeed, index: output.index
            ),
            treeID: output.treeID
        )

        #expect(utxo.hash.bigEndianBytes == (try fixtureBytes(output.commitment)))
    }

    /// Verifies empty-UTXO hashes against zolana's published values and an independently derived
    /// value.
    ///
    /// The published values are the empty UTXO of the blinding-seed vector and the padding inputs of
    /// the transfers in `hash_vectors.rs`. The last case, in the last tree with r - 1 as the
    /// blinding, comes from a separate Python implementation of Poseidon.
    ///
    /// - Parameters:
    ///   - treeID: The ID of the slot's tree.
    ///   - blinding: The slot's blinding.
    ///   - hex: The expected hash.
    @Test(arguments: try UTXOTests.emptyUTXOs())
    func `Empty-UTXO hashes match the published and independently derived values`(
        treeID: UInt16,
        blinding: Poseidon.Element,
        hex: String
    ) throws {
        #expect(UTXO.dummyHash(treeID: treeID, blinding: blinding).bigEndianBytes == (try fixtureBytes(hex)))
    }

    /// Verifies UTXO hashes against independently derived values.
    ///
    /// Each case has the same owner and blinding. The mints are SOL's, 32 zero bytes, and USDC's,
    /// `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`; each mint has the amounts 0, 1, and the
    /// largest UInt64, split between the first and the last tree. The tree IDs 0 and 65535 read the
    /// same in either byte order, so a SOL case in tree 258, 0x0102, checks the tree ID's byte order.
    ///
    /// - Parameters:
    ///   - mint: The 32-byte mint address.
    ///   - amount: The amount.
    ///   - treeID: The ID of the tree that holds the UTXO.
    ///   - hex: The expected hash.
    @Test(arguments: [
        (
            "0000000000000000000000000000000000000000000000000000000000000000", 0, 0,
            "254c1355cf5d096711abd71c874f815f5bf9a46fc70cc31d5e780458fefd2ec8"
        ),
        (
            "0000000000000000000000000000000000000000000000000000000000000000", 1, .max,
            "11641733195ca24d891dfaa6f7e98f53d2ac0ff62e518ed9375cc4c1954565fa"
        ),
        (
            "0000000000000000000000000000000000000000000000000000000000000000", .max, 0,
            "15d29a2046b1efa94321c8324f9e1449be37c7d6338198176970f709f3c1b3f8"
        ),
        (
            "0000000000000000000000000000000000000000000000000000000000000000", 1, 258,
            "2955117cb93fa5f46fb1b03f108904911f6dd874b98e75638407694251d40629"
        ),
        (
            "c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61", 0, .max,
            "0a658aed74d0449f876305eb7fa90c859be24013cc1ee21c75658de3f50e8678"
        ),
        (
            "c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61", 1, 0,
            "11bfdfed1491f99177a4aedf919fa43f140ec1ad30071744bd6601f4d2c9d32c"
        ),
        (
            "c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61", .max, .max,
            "0d72ecb2cc24de96aeb1d604ddaac69d87e473fcf2dccd0f1e24a26643f2a911"
        ),
    ] as [(String, UInt64, UInt16, String)])
    func `Hashes match independently derived values`(mint: String, amount: UInt64, treeID: UInt16, hex: String) throws {
        let utxo = UTXO(owner: owner, mint: try fixtureBytes(mint), amount: amount, blinding: blinding, treeID: treeID)

        #expect(utxo.hash.bigEndianBytes == (try fixtureBytes(hex)))
    }

    /// Verifies the nullifier of a UTXO owned by zolana's Ed25519 rail against an independently
    /// derived value.
    ///
    /// The UTXO holds one lamport in the first tree, so its nullifier covers its hash, its
    /// blinding, and the rail's nullifier secret.
    @Test
    func `Nullifiers match an independently derived value`() throws {
        let utxo = UTXO(owner: owner, mint: Array(repeating: 0, count: 32), amount: 1, blinding: blinding, treeID: 0)

        #expect(utxo.nullifier(using: nullifierKey).bigEndianBytes == (try fixtureBytes("0cd4871b07798e5135b2556f8c8ca0becca860a35ca286ab5b3a2215d920ee8f")))
    }

    /// Gathers the empty-UTXO cases: the published blinding-seed vector, the published padding
    /// inputs, and one independently derived value.
    ///
    /// - Returns: Each case's tree ID, blinding, and expected hash.
    /// - Throws: A test failure if the fixture is missing or malformed, or an error if it can't be
    ///   read or decoded.
    private static func emptyUTXOs() throws -> [(UInt16, Poseidon.Element, String)] {
        let vector = try CommitmentVectors.load().dummyUTXOHash
        return [(vector.treeID, Poseidon.Element(vector.blinding), vector.hash)]
            + TransferVectors.paddingInputs.map { ($0.treeID, TransferVectors.blinding($0.blindingByte), $0.hash) }
            + [(.max, -.one, "00eee5890d80f5abd0d2e680a10c7bf7b94abf25d5b94b110e6132cec38e7848")]
    }
}
